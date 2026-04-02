class FederationPortalsController < ApplicationController

  namespace "/federation_portals" do

    # search?q=water&portals=agroportal,ecoportal,nvs
    get '/search' do
      query = params[:query] || params[:q]
      error 400, "You must provide a 'query' parameter to execute a search" if query.nil? || query.strip.empty?

      portals = selected_portals(params)
      results = federated_portal_search(portals, query, params)

      current_page = (params[:page] || 1).to_i
      pagesize = (params[:pagesize] || 50).to_i
      total_count = results[:totalCount]
      page_count = (total_count / pagesize.to_f).ceil

      page_data = {
        page: current_page,
        pageCount: page_count,
        totalCount: total_count,
        prevPage: current_page > 1 ? current_page - 1 : nil,
        nextPage: current_page < page_count ? current_page + 1 : nil,
        collection: results[:collection]
      }
      page_data[:errors] = results[:errors] if results[:errors].any?

      content_type 'application/json'
      MultiJson.dump(page_data)
    end

  end

end
