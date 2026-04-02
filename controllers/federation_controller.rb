require 'faraday'
require 'parallel'

class FederationController < ApplicationController

  GATEWAY_URL = "https://terminology.services.base4nfdi.de/api-gateway"
  GATEWAY_CONNECTION = Faraday.new(url: GATEWAY_URL) do |conn|
    conn.headers['Accept'] = 'application/json'
    conn.options.timeout = 30
    conn.options.open_timeout = 10
  end

  namespace "/api/federation" do

    get '/search' do
      query = params[:query] || params[:q]

      if query.nil? || query.strip.empty?
        error 400, "You must provide a 'query' parameter to execute a search"
      end

      databases = (params[:database] || "ontoportal,nerc").split(',').map(&:strip)

      # Appels parallèles : un par database pour éviter la limitation du Gateway
      gateway_results = Parallel.map(databases, in_threads: databases.size) do |db|
        fetch_gateway(query, db)
      end

      docs = []
      errors = []

      gateway_results.each do |result|
        if result[:error]
          errors << result[:error]
        else
          result[:items].each do |item|
            if item["backend_type"] == "nerc"
              docs << map_nvs_item(item)
            else
              docs << map_ontoportal_item(item)
            end
          end
        end
      end

      total_found = docs.size

      page_data = paginate(docs, total_found)
      page_data[:errors] = errors if errors.any?

      content_type 'application/json'
      MultiJson.dump(page_data)
    end

  end

  helpers do
    def fetch_gateway(query, database)
      response = GATEWAY_CONNECTION.get("search", { query: query, database: database })

      if response.success?
        data = MultiJson.load(response.body)
        items = if data.is_a?(Array)
                  data
                elsif data.is_a?(Hash) && data["collection"]
                  data["collection"]
                else
                  []
                end
        { items: items }
      else
        { error: "Gateway (#{database}) returned HTTP #{response.status}" }
      end
    rescue => e
      { error: "Gateway (#{database}): #{e.message}" }
    end

    def map_ontoportal_item(item)
      acronym = item["ontology"]
      source_api = item["source"]
      source_name = item["source_name"]
      ontology_iri = item["ontology_iri"] || "#{source_api}/ontologies/#{acronym}"
      concept_id = item["@id"] || item["iri"]
      encoded_id = CGI.escape(concept_id)

      {
        "prefLabel" => item["label"],
        "synonym" => Array(item["synonyms"]),
        "definition" => Array(item["descriptions"]),
        "obsolete" => item["obsolete"] || false,
        "matchType" => nil,
        "ontologyType" => nil,
        "hasChildren" => item["hasChildren"] || false,
        "@id" => concept_id,
        "@type" => item["type"] || "http://www.w3.org/2002/07/owl#Class",
        "links" => {
          "self" => "#{source_api}/ontologies/#{acronym}/classes/#{encoded_id}",
          "ontology" => ontology_iri,
          "children" => "#{source_api}/ontologies/#{acronym}/classes/#{encoded_id}/children",
          "parents" => "#{source_api}/ontologies/#{acronym}/classes/#{encoded_id}/parents",
          "descendants" => "#{source_api}/ontologies/#{acronym}/classes/#{encoded_id}/descendants",
          "ancestors" => "#{source_api}/ontologies/#{acronym}/classes/#{encoded_id}/ancestors",
          "instances" => "#{source_api}/ontologies/#{acronym}/classes/#{encoded_id}/instances",
          "tree" => "#{source_api}/ontologies/#{acronym}/classes/#{encoded_id}/tree",
          "notes" => "#{source_api}/ontologies/#{acronym}/classes/#{encoded_id}/notes",
          "mappings" => "#{source_api}/ontologies/#{acronym}/classes/#{encoded_id}/mappings",
          "ui" => item["source_url"] || "#{source_api}/ontologies/#{acronym}?p=classes&conceptid=#{encoded_id}"
        },
        "source_portal" => source_name
      }
    end

    def map_nvs_item(item)
      concept_id = item["@id"] || item["iri"]

      {
        "prefLabel" => item["label"],
        "synonym" => Array(item["synonyms"]),
        "definition" => Array(item["descriptions"]),
        "obsolete" => item["obsolete"] || false,
        "matchType" => nil,
        "ontologyType" => nil,
        "hasChildren" => item["hasChildren"] || false,
        "@id" => concept_id,
        "@type" => item["type"] || "http://www.w3.org/2004/02/skos/core#Concept",
        "links" => {
          "self" => concept_id,
          "ontology" => item["ontology_iri"] || item["ontology"],
          "children" => Array(item["children"]),
          "parents" => [],
          "descendants" => [],
          "ancestors" => [],
          "instances" => [],
          "tree" => nil,
          "notes" => [],
          "mappings" => [],
          "ui" => concept_id
        },
        "source_portal" => "nvs"
      }
    end

    def paginate(docs, total_found)
      current_page = (params[:page] || 1).to_i
      pagesize = (params[:pagesize] || 50).to_i
      page_count = (total_found / pagesize.to_f).ceil
      start_index = (current_page - 1) * pagesize
      paged_docs = docs[start_index, pagesize] || []

      {
        page: current_page,
        pageCount: page_count,
        totalCount: total_found,
        prevPage: current_page > 1 ? current_page - 1 : nil,
        nextPage: current_page < page_count ? current_page + 1 : nil,
        collection: paged_docs
      }
    end
  end

end
