require 'faraday'

class FederationPortalsController < ApplicationController

  FEDERATION_PORTALS = {
    earthportal: {url: 'https://data.earthportal.eu', apikey: '9a3f9f33-f512-4a04-bb84-45636068e255' },                                                                                                                                                   
    agroportal: {url: 'https://data.agroportal.lirmm.fr', apikey: '1cfae05f-9e67-486f-820b-b393dec5764b' },
    ecoportal: {url: 'https://data.ecoportal.lifewatch.eu', apikey: '43a437ba-a437-4bf0-affd-ab520e584719' },
    biodivportal: {url: 'https://data.biodivportal.gfbio.org', apikey: '47a57aa3-7b54-4f34-b695-dbb5f5b7363e' }
  }

  NVS_URL = 'https://vocab.nerc.ac.uk'

  namespace "/api/federation_portals" do

    get '/search' do
      query = params[:query] || params[:q]

      if query.nil? || query.strip.empty?
        error 400, "You must provide a 'query' parameter to execute a search"
      end

      
      portals_threads = FEDERATION_PORTALS.map do |name, config|
        Thread.new do
          begin
            conn = Faraday.new(url: config[:url]) do |f|
              f.headers['Accept'] = 'application/json'
              f.options.timeout = 30
            end

            response = conn.get('/search', {
              q: query,
              apikey: config[:apikey],
              pagesize: params[:pagesize] || 50,
              page: params[:page] || 1
            })

            if response.success?
              data = JSON.parse(response.body)
              if data["collection"]
                data["collection"].each do |item|
                  item["source_portal"] = name.to_s
                end
              end
              data
            else
              nil
            end
          rescue => e
            nil
          end
        end
      end

      nvs_thread = Thread.new do
        begin
          conn = Faraday.new(url: NVS_URL) do |f|
            f.headers['Accept'] = 'application/json'
            f.options.timeout = 30
          end

          response = conn.get('/search/content', {
            q: query,
            pagesize: params[:pagesize] || 50,
            page: params[:page] || 1
          })

          if response.success?
            data = JSON.parse(response.body)
            collections = (data["member"] || []).map do |item|
              {
                "prefLabel" => item["sdo:name"],
                "synonym" => [],
                "definition" => [],
                "obsolete" => false,
                "matchType" => nil,
                "ontologyType" => nil,
                "hasChildren" => false,
                "@id" => item["@id"],
                "@type" => "http://www.w3.org/2004/02/skos/core#Concept",
                "links" => {
                  "self" => item["@id"],
                  "ontology" => item["sdo:inDefinedTermSet"],
                  "children" => [],
                  "parents" => [],
                  "descendants" => [],
                  "ancestors" => [],
                  "instances" => [],
                  "tree" => nil,
                  "notes" => [],
                  "mappings" => [],
                  "ui" => item["@id"]
                },
                "source_portal" => "nvs"
              }
            end

            # Enrichir chaque concept avec les détails NVS (broader, narrower, definition, synonym...)
            enrich_threads = collections.map do |concept|
              Thread.new do
                begin
                  detail_url = concept["@id"]
                  next unless detail_url
                  # Ajouter le trailing slash si absent (NVS redirige 301 sans slash)
                  detail_url = detail_url + '/' unless detail_url.end_with?('/')

                  detail_conn = Faraday.new(url: detail_url) do |f|
                    f.headers['Accept'] = 'application/ld+json'
                    f.options.timeout = 10
                  end

                  detail_response = detail_conn.get('', {
                    _profile: 'nvs',
                    _mediatype: 'application/ld+json'
                  })

                  if detail_response.success?
                    detail = JSON.parse(detail_response.body)

                    broader = Array(detail["skos:broader"])
                    narrower = Array(detail["skos:narrower"])
                    same_as = Array(detail["owl:sameAs"])

                    concept["definition"] = detail["skos:definition"] ? [detail["skos:definition"]] : []
                    concept["synonym"] = detail["skos:altLabel"] ? Array(detail["skos:altLabel"]) : []
                    concept["obsolete"] = detail["owl:deprecated"] || false
                    concept["hasChildren"] = !narrower.empty?

                    concept["links"]["parents"] = broader.map { |b| b.is_a?(Hash) ? b["@id"] : b.to_s }
                    concept["links"]["children"] = narrower.map { |n| n.is_a?(Hash) ? n["@id"] : n.to_s }
                    concept["links"]["notes"] = detail["skos:note"] ? [detail["skos:note"]] : []
                    concept["links"]["mappings"] = same_as.map { |s| s.is_a?(Hash) ? s["@id"] : s.to_s }
                  end
                rescue => e
                  # en cas d'erreur, on garde les champs par défaut
                end
              end
            end

            enrich_threads.each(&:join)

            total = data["totalItems"] || collections.size
            {"collection" => collections, "totalCount" => total}
          else
            nil
          end
        rescue => e
          nil
        end
      end

      all_threads = portals_threads + [nvs_thread]

      # waiting results
      results = []
      all_threads.each do |thread|
        result = thread.value
        results.push(result)
      end

      results.compact!

      # merger les collections
      all_docs = []
      total_count = 0

      results.each do |portal_result|
        all_docs.concat(portal_result["collection"] || [])
        total_count += (portal_result["totalCount"] || 0)
      end

      # return results avec pagination info
      page, page_size = page_params
      page_count = total_count > 0 ? (total_count / page_size.to_f).ceil : 0
      content_type :json
      {
        "page"       => page,
        "pageCount"  => page_count,
        "totalCount" => total_count,
        "prevPage"   => page > 1 ? page - 1 : nil,
        "nextPage"   => page < page_count ? page + 1 : nil,
        "collection" => all_docs
      }.to_json
    end

  end


end
