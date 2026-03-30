require 'faraday'

class FederationController < ApplicationController

  GATEWAY_URL = "https://terminology.services.base4nfdi.de/api-gateway"
  GATEWAY_CONNECTION = Faraday.new(url: GATEWAY_URL) do |conn|
    conn.headers['Accept'] = 'application/json'
  end


  namespace "/api/federation" do

    get'/search' do
      query = params[:query] || params[:q]

      if query.nil? || query.strip.empty?
        error 400, "You must provide a 'query' parameter to execute a search"
      end

      gateway_params = {query: query, database: "ontoportal"}

      response = GATEWAY_CONNECTION.get("search", gateway_params)

      unless response.success?
        error response.status, "API Gateway error: #{response.body}"
      end

      gateway_response_data = JSON.parse(response.body)
      results = gateway_response_data.is_a?(Array) ? gateway_response_data : []

      docs = []

      results.each do |item|                   
        acronym      = item["ontology"]                                                       
        ontology_iri = item["ontology_iri"] || item["source"].to_s + "/ontologies/" + acronym.to_s                                                                                          
                                                                                              
        doc = {                                                                               
          id:         item["@id"] || item["iri"],                                             
          prefLabel:  item["label"],                                                          
          synonym:    Array(item["synonyms"]) ,                                                 
          definition: Array(item["descriptions"]),                                             
          obsolete:   item["obsolete"] || false,                                              
          matchType:  "",                 
          ontologyType: "",                                           
          ontology_rank: 0.0                                                                  
        }   

        ontology = LinkedData::Models::Ontology.read_only(
          id: ontology_iri,
          acronym: acronym
        )
        
        submission = LinkedData::Models::OntologySubmission.read_only(
          id: ontology_iri ,
          ontology: ontology
        )

        doc[:submission] = submission

        instance = LinkedData::Models::Class.read_only(doc)
        docs.push(instance)

      end

      total_found = results.size

      reply 200, page_object(docs, total_found)
    end

  end

end
