class ConnectorController < ApplicationController
  namespace "/connector" do
    get "/projects" do
      validate_source!
      begin
        connector = Connectors::Factory.create(@source)
        response = connector.fetch_projects(params)
        reply 200, response
      rescue StandardError => e
        error 500, { error: e.message }
      end
    end
  
    private
    def validate_source!
      @source = params[:source]&.upcase
      error 400, { error: "Source parameter is required" } if @source.nil?
      valid_sources = LinkedData.settings.connectors[:available_sources].keys
      error 400, { error: "Invalid source. Valid sources: #{valid_sources.join(', ')}" } unless valid_sources.include?(@source)
    end
  end
end