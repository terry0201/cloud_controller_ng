require 'securerandom'
require 'openssl'
require 'openssl/cipher'
require 'openssl/digest'

require 'base64'

module VCAP::CloudController
  module Encryptor
    class << self
      ALGORITHM = 'AES-128-CBC'.freeze

      def generate_salt
        SecureRandom.hex(8).to_s
      end

      def encrypt(input, salt)
        return unless input

        label = current_encryption_key_label
        key = key_to_use(label)

        encrypt_raw(input, key, salt)
      end

      def encrypt_raw(input, key, salt)
        Base64.strict_encode64(run_cipher(make_cipher.encrypt, input, salt, key))
      end

      def decrypt(encrypted_input, salt, label=nil)
        return unless encrypted_input

        key = key_to_use(label)

        decrypt_raw(encrypted_input, key, salt)
      end

      def decrypt_raw(encrypted_input, key, salt)
        run_cipher(make_cipher.decrypt, Base64.decode64(encrypted_input), salt, key)
      end

      def encrypted_classes
        @encrypted_classes ||= []
      end

      attr_writer :db_encryption_key
      attr_writer :database_encryption_keys
      attr_accessor :current_encryption_key_label

      private

      attr_reader :db_encryption_key
      attr_writer :encrypted_classes

      def database_encryption_keys
        @database_encryption_keys ||= {}
      end

      def key_to_use(label)
        database_encryption_keys.fetch(label&.to_sym, db_encryption_key)
      end

      def make_cipher
        OpenSSL::Cipher.new(ALGORITHM)
      end

      def run_cipher(cipher, input, salt, key)
        if deprecated_short_salt?(salt)
          cipher.pkcs5_keyivgen(key, salt)
        else
          cipher.key = OpenSSL::PKCS5.pbkdf2_hmac(key, salt, 2048, 16, OpenSSL::Digest::SHA256.new)
          cipher.iv = salt
        end
        cipher.update(input) << cipher.final
      end

      def deprecated_short_salt?(salt)
        salt.length == 8
      end
    end

    module FieldEncryptor
      extend ActiveSupport::Concern

      private

      def update_encryption_key
        return if Encryptor.current_encryption_key_label.nil?
        return if encryption_key_label == Encryptor.current_encryption_key_label

        db.transaction do
          (self.class.all_encrypted_fields || []).each do |field|
            current_value = send("#{field[:field_name]}_with_encryption")
            updated_encrypted_value = Encryptor.encrypt(current_value, send(field[:salt_name]))
            send("#{field[:field_name]}_without_encryption=", updated_encrypted_value)
          end
          self.encryption_key_label = Encryptor.current_encryption_key_label
        end
      end

      module ClassMethods
        def all_encrypted_fields
          if self.superclass.respond_to? :all_encrypted_fields
            encrypted_fields + self.superclass.all_encrypted_fields
          else
            encrypted_fields
          end
        end

        private

        def encrypted_fields
          @encrypted_fields ||= []
        end

        def set_field_as_encrypted(field_name, options={})
          field_name = field_name.to_sym
          salt_name = (options[:salt] || 'salt').to_sym
          storage_column = options[:column]
          raise "Salt field `#{salt_name}` does not exist" unless columns.include?(salt_name)
          raise 'Field "encryption_key_label" does not exist' unless columns.include?(:encryption_key_label)

          encrypted_fields << { field_name: field_name, salt_name: salt_name }

          Encryptor.encrypted_classes << self.name

          define_method "generate_#{salt_name}" do
            return if send(salt_name).present?

            send("#{salt_name}=", Encryptor.generate_salt)
          end

          if storage_column
            alias_method field_name, storage_column
            alias_method "#{field_name}=", "#{storage_column}="
          end

          define_method "#{field_name}_with_encryption" do
            Encryptor.decrypt(send("#{field_name}_without_encryption"), send(salt_name), encryption_key_label)
          end
          alias_method "#{field_name}_without_encryption", field_name
          alias_method field_name, "#{field_name}_with_encryption"

          define_method "#{field_name}_with_encryption=" do |value|
            send("generate_#{salt_name}")
            db.transaction do
              update_encryption_key
              encrypted_value = Encryptor.encrypt(value.presence, send(salt_name))
              send("#{field_name}_without_encryption=", encrypted_value)
            end
          end
          alias_method "#{field_name}_without_encryption=", "#{field_name}="
          alias_method "#{field_name}=", "#{field_name}_with_encryption="
        end
      end
    end
  end
end
