require 'presenters/v3/stack_presenter'
require 'actions/stack_create'
require 'messages/stack_create_message'
require 'messages/stacks_list_message'
require 'fetchers/stack_list_fetcher'

class StacksController < ApplicationController
  def index
    message = StacksListMessage.from_params(query_params)
    invalid_param!(message.errors.full_messages) unless message.valid?

    dataset = StackListFetcher.new.fetch_all(message)

    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::StackPresenter,
      paginated_result: SequelPaginator.new.get_page(dataset, message.try(:pagination_options)),
      path: '/v3/stacks',
      message: message
    )
  end

  def create
    unauthorized! unless permission_queryer.can_write_globally?

    message = StackCreateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    stack = StackCreate.new.create(message)

    render status: :created, json: Presenters::V3::StackPresenter.new(stack)
  rescue StackCreate::Error => e
    unprocessable! e
  end

  def show
    stack = Stack.find(guid: hashed_params[:guid])
    stack_not_found! unless stack

    render status: :ok, json: Presenters::V3::StackPresenter.new(stack)
  end

  def destroy
    unauthorized! unless permission_queryer.can_write_globally?

    stack = Stack.find(guid: hashed_params[:guid])
    stack_not_found! unless stack

    begin
      stack.destroy
    rescue Stack::AppsStillPresentError
      unprocessable! "Cannot delete stack '#{stack.name}' because apps are currently using the stack."
    end

    head :no_content
  end

  private

  def stack_not_found!
    resource_not_found!(:stack)
  end
end
