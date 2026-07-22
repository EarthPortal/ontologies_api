class ExternalToolsController < ApplicationController

  namespace "/external_tools" do
    # Display all external tools
    get do
      check_last_modified_collection(LinkedData::Models::ExternalTool)
      tools = ExternalTool.where.include(ExternalTool.goo_attrs_to_load(includes_param)).to_a
      reply tools
    end

    # Display a single external tool
    get '/:name' do
      check_last_modified_collection(LinkedData::Models::ExternalTool)
      name = params["name"]
      tool = ExternalTool.find(name).include(ExternalTool.goo_attrs_to_load(includes_param)).first
      error 404, "External tool #{name} not found" if tool.nil?
      reply 200, tool
    end

    post do
      create_external_tool
    end

    # Create an external tool with the given name
    put '/:name' do
      create_external_tool
    end

    # Update an existing external tool
    patch '/:name' do
      name = params["name"]
      tool = ExternalTool.find(name).include(ExternalTool.attributes).first

      if tool.nil?
        error 400, "External tool does not exist, please create using HTTP PUT before modifying"
      else
        populate_from_params(tool, params)

        if tool.valid?
          tool.save
        else
          error 400, tool.errors
        end
      end
      halt 204
    end

    # Delete an external tool
    delete '/:name' do
      tool = ExternalTool.find(params["name"]).first
      tool.delete
      halt 204
    end

    private

    def create_external_tool
      params ||= @params
      name = params["name"]
      tool = ExternalTool.find(name).first

      if tool.nil?
        tool = instance_from_params(ExternalTool, params)
      else
        error 400, "External tool exists, please use HTTP PATCH to update"
      end

      if tool.valid?
        tool.save
      else
        error 400, tool.errors
      end
      reply 201, tool
    end

  end
end
