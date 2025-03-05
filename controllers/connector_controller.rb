class ConnectorController < ApplicationController
  namespace "/connector" do
    VALID_SOURCES = ['ANR', 'CORDIS'].freeze

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
      error 400, { error: "Invalid source. Valid sources: #{VALID_SOURCES.join(', ')}" } unless VALID_SOURCES.include?(@source)
    end
  end
end