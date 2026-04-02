require 'sinatra/base'
require 'faraday'
require 'parallel'

module Sinatra
  module Helpers
    module FederationPortalsHelper

      NVS_URL = 'https://vocab.nerc.ac.uk'

      def selected_portals(params)
        all_portals = LinkedData.settings.federated_portals || {}

        if params[:portals].present?
          selected = params[:portals].split(',').map(&:strip).map(&:downcase)
          all_portals.select { |name, _| selected.include?(name.to_s.downcase) }
        else
          all_portals
        end
      end

      def include_nvs?(params)
        return true unless params[:portals].present?
        params[:portals].split(',').map(&:strip).map(&:downcase).include?('nvs')
      end

      def federated_portal_search(portals, query, params)
        all_sources = portals.map { |name, config| { type: :portal, name: name, config: config } }
        all_sources << { type: :nvs } if include_nvs?(params)

        results = Parallel.map(all_sources, in_threads: all_sources.size) do |source|
          if source[:type] == :nvs
            nvs_search(query, params)
          else
            portal_search(source[:name], source[:config], query, params)
          end
        end

        merge_results(results)
      end

      def portal_search(name, config, query, params)
        name = name.to_s
        cache_key = "federation_portal_up_#{name}"

        cached_status = Sinatra::Helpers::HTTPCacheHelper::REDIS.get(cache_key) rescue nil
        if cached_status == "false"
          return { portal: name, error: "#{name} is down (cached for 10 minutes)" }
        end

        api_url = config[:api] || config['api']
        apikey = config[:apikey] || config['apikey']

        conn = Faraday.new(url: api_url) do |f|
          f.headers['Accept'] = 'application/json'
          f.headers['Authorization'] = "apikey token=#{apikey}"
          f.options.timeout = 15
          f.options.open_timeout = 5
        end

        response = conn.get('/search', {
          q: query,
          pagesize: params[:pagesize] || 50,
          page: params[:page] || 1
        })

        if [301, 302].include?(response.status) && response.headers['location']
          response = conn.get(response.headers['location'])
        end

        if response.success?
          data = MultiJson.load(response.body)
          collection = data["collection"] || []
          collection.each do |item|
            item["source_portal"] = name
          end
          { portal: name, collection: collection, totalCount: data["totalCount"] || collection.size }
        else
          { portal: name, error: "#{name} returned HTTP #{response.status}" }
        end

      rescue => e
        Sinatra::Helpers::HTTPCacheHelper::REDIS.setex(cache_key, 600, "false") rescue nil
        { portal: name, error: "Problem retrieving #{name}: #{e.message}" }
      end

      def nvs_search(query, params)
        cache_key = "federation_portal_up_nvs"

        cached_status = Sinatra::Helpers::HTTPCacheHelper::REDIS.get(cache_key) rescue nil
        if cached_status == "false"
          return { portal: "nvs", error: "nvs is down (cached for 10 minutes)" }
        end

        conn = Faraday.new(url: NVS_URL) do |f|
          f.headers['Accept'] = 'application/json'
          f.options.timeout = 15
          f.options.open_timeout = 5
        end

        response = conn.get('/search/content', {
          q: query,
          pagesize: params[:pagesize] || 50,
          page: params[:page] || 1
        })

        if [301, 302].include?(response.status) && response.headers['location']
          response = conn.get(response.headers['location'])
        end

        if response.success?
          data = MultiJson.load(response.body)
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

          enrich_nvs_concepts_sparql(collections)

          total = data["totalItems"] || collections.size
          { portal: "nvs", collection: collections, totalCount: total }
        else
          { portal: "nvs", error: "nvs returned HTTP #{response.status}" }
        end

      rescue => e
        Sinatra::Helpers::HTTPCacheHelper::REDIS.setex(cache_key, 600, "false") rescue nil
        { portal: "nvs", error: "Problem retrieving nvs: #{e.message}" }
      end




      # Solution A — N appels individuels (ancien, fallback)
      def enrich_nvs_concepts_individual(collections)
        Parallel.each(collections, in_threads: [collections.size, 10].min) do |concept|
          detail_url = concept["@id"]
          next unless detail_url

          detail_url = detail_url + '/' unless detail_url.end_with?('/')

          conn = Faraday.new(url: detail_url) do |f|
            f.headers['Accept'] = 'application/ld+json'
            f.options.timeout = 10
            f.options.open_timeout = 5
          end

          response = conn.get('', {
            _profile: 'nvs',
            _mediatype: 'application/ld+json'
          })

          if response.success?
            detail = MultiJson.load(response.body)

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
          # En cas d'erreur, on garde les champs par défaut
        end
      end

      NVS_SPARQL_URL = 'https://vocab.nerc.ac.uk/sparql/sparql'

      # Solution B — 1 seul appel SPARQL batch (nouveau, rapide)
      def enrich_nvs_concepts_sparql(collections)
        return if collections.empty?

        iris = collections.map { |c| c["@id"] }.compact
        return if iris.empty?

        values = iris.map { |iri|
          uri = iri.end_with?('/') ? iri : "#{iri}/"
          "<#{uri}>"
        }.join(' ')

        sparql_query = <<~SPARQL
          PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
          PREFIX owl: <http://www.w3.org/2002/07/owl#>
          SELECT ?s ?definition ?altLabel ?broader ?narrower ?deprecated ?sameAs ?note WHERE {
            VALUES ?s { #{values} }
            OPTIONAL { ?s skos:definition ?definition }
            OPTIONAL { ?s skos:altLabel ?altLabel }
            OPTIONAL { ?s skos:broader ?broader }
            OPTIONAL { ?s skos:narrower ?narrower }
            OPTIONAL { ?s owl:deprecated ?deprecated }
            OPTIONAL { ?s owl:sameAs ?sameAs }
            OPTIONAL { ?s skos:note ?note }
          }
        SPARQL

        conn = Faraday.new(url: NVS_SPARQL_URL) do |f|
          f.request :url_encoded
          f.headers['Accept'] = 'application/sparql-results+json'
          f.options.timeout = 15
          f.options.open_timeout = 5
        end

        response = conn.post('', query: sparql_query)
        return unless response.success?

        data = MultiJson.load(response.body)
        bindings = data.dig("results", "bindings") || []

        # Regrouper les résultats SPARQL par IRI
        grouped = {}
        bindings.each do |row|
          uri = row.dig("s", "value")
          next unless uri
          grouped[uri] ||= { definitions: [], altLabels: [], broaders: [], narrowers: [], sameAs: [], notes: [], deprecated: false }
          g = grouped[uri]

          val = row.dig("definition", "value")
          g[:definitions] << val if val && !val.empty? && !g[:definitions].include?(val)

          val = row.dig("altLabel", "value")
          g[:altLabels] << val if val && !val.empty? && !g[:altLabels].include?(val)

          val = row.dig("broader", "value")
          g[:broaders] << val if val && !g[:broaders].include?(val)

          val = row.dig("narrower", "value")
          g[:narrowers] << val if val && !g[:narrowers].include?(val)

          val = row.dig("sameAs", "value")
          g[:sameAs] << val if val && !g[:sameAs].include?(val)

          val = row.dig("note", "value")
          g[:notes] << val if val && !val.empty? && !g[:notes].include?(val)

          val = row.dig("deprecated", "value")
          g[:deprecated] = true if val == "true"
        end

        # Appliquer l'enrichissement à chaque concept
        collections.each do |concept|
          iri = concept["@id"]
          iri_with_slash = iri&.end_with?('/') ? iri : "#{iri}/"
          enrichment = grouped[iri] || grouped[iri_with_slash]
          next unless enrichment

          concept["definition"] = enrichment[:definitions]
          concept["synonym"] = enrichment[:altLabels]
          concept["obsolete"] = enrichment[:deprecated]
          concept["hasChildren"] = !enrichment[:narrowers].empty?

          concept["links"]["parents"] = enrichment[:broaders]
          concept["links"]["children"] = enrichment[:narrowers]
          concept["links"]["notes"] = enrichment[:notes]
          concept["links"]["mappings"] = enrichment[:sameAs]
        end
      end


      

      def merge_results(results)
        collection = []
        errors = []
        total_count = 0

        results.each do |result|
          if result[:error]
            errors << result[:error]
          else
            collection.concat(result[:collection])
            total_count += result[:totalCount]
          end
        end

        seen = {}
        merged = []

        collection.each do |item|
          concept_id = item["@id"]
          ontology_acronym = item.dig("links", "ontology")&.split('/')&.last
          dedup_key = "#{concept_id}||#{ontology_acronym}"

          if seen[dedup_key]
            portal_name = item["source_portal"]
            seen[dedup_key]["other_portals"] << portal_name
          else
            item["other_portals"] = []
            seen[dedup_key] = item
            merged << item
          end
        end

        { collection: merged, totalCount: total_count, errors: errors }
      end

    end
  end
end

helpers Sinatra::Helpers::FederationPortalsHelper
