require 'spec_helper'
require 'messages/apps_list_message'

module VCAP::CloudController
  RSpec.describe AppListFetcher do
    describe '#fetch' do
      let(:space) { Space.make }
      let(:app) { AppModel.make(space_guid: space.guid) }
      let(:sad_app) { AppModel.make(space_guid: space.guid) }
      let(:org) { space.organization }
      let(:fetcher) { AppListFetcher.new }
      let(:space_guids) { [space.guid] }
      let(:pagination_options) { PaginationOptions.new({}) }
      let(:filters) { {} }
      let(:message) { AppsListMessage.from_params(filters) }
      let(:apps) { fetcher.fetch(message, space_guids) }

      before do
        app.save
        sad_app.save
        expect(message).to be_valid
      end

      it 'fetch_all includes all the apps' do
        app = AppModel.make
        expect(fetcher.fetch_all(message).all).to include(app)
      end

      context 'when no filters are specified' do
        it 'returns all of the desired apps' do
          expect(apps.all).to include(app, sad_app)
        end
      end

      context 'when the app names are provided' do
        let(:filters) { { names: [app.name] } }

        it 'returns all of the desired apps' do
          expect(apps.all).to include(app)
          expect(apps.all).to_not include(sad_app)
        end
      end

      context 'when the app space_guids are provided' do
        let(:filters) { { space_guids: [space.guid] } }
        let(:sad_app) { AppModel.make }

        it 'returns all of the desired apps' do
          expect(apps.all).to include(app)
          expect(apps.all).to_not include(sad_app)
        end
      end

      context 'when the organization guids are provided' do
        let(:filters) { { organization_guids: [org.guid] } }
        let(:sad_org) { Organization.make }
        let(:sad_space) { Space.make(organization_guid: sad_org.guid) }
        let(:sad_app) { AppModel.make(space_guid: sad_space.guid) }
        let(:space_guids) { [space.guid, sad_space.guid] }

        it 'returns all of the desired apps' do
          expect(apps.all).to include(app)
          expect(apps.all).to_not include(sad_app)
        end
      end

      context 'when the app guids are provided' do
        let(:filters) { { guids: [app.guid] } }

        it 'returns all of the desired apps' do
          expect(apps.all).to include(app)
          expect(apps.all).to_not include(sad_app)
        end
      end

      context 'when a label_selector is provided' do
        let(:filters) { { 'label_selector' => 'dog in (chihuahua,scooby-doo)' } }
        let!(:app_label) do
          VCAP::CloudController::AppLabelModel.make(resource_guid: app.guid, key_name: 'dog', value: 'scooby-doo')
        end
        let!(:sad_app_label) do
          VCAP::CloudController::AppLabelModel.make(resource_guid: sad_app.guid, key_name: 'dog', value: 'poodle')
        end

        it 'returns all of the desired apps' do
          expect(apps.all).to include(app)
          expect(apps.all).to_not include(sad_app)
        end

        context 'and other filters are present' do
          let!(:happiest_app) { AppModel.make(space_guid: space.guid, name: 'bob') }
          let!(:happiest_app_label) do
            VCAP::CloudController::AppLabelModel.make(resource_guid: happiest_app.guid, key_name: 'dog', value: 'scooby-doo')
          end
          let(:filters) { { 'names' => 'bob', 'label_selector' => 'dog in (chihuahua,scooby-doo)' } }

          it 'returns the desired app' do
            expect(apps.all).to contain_exactly(happiest_app)
          end
        end
      end
    end
  end
end
