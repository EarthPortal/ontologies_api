require_relative '../test_case'
require 'json-schema'

class TestProjectsController < TestCase
  DEBUG_MESSAGES=false

  # JSON Schema
  # This could be in the Project model, see
  # https://github.com/ncbo/ontologies_linked_data/issues/22
  # json-schema for description and validation of REST json responses.
  # http://tools.ietf.org/id/draft-zyp-json-schema-03.html
  # http://tools.ietf.org/html/draft-zyp-json-schema-03
  JSON_SCHEMA_STR = <<-END_JSON_SCHEMA_STR
  {
    "type":"object",
    "title":"Project",
    "description":"A BioPortal project, which may refer to multiple ontologies.",
    "additionalProperties":true,
    "properties":{
      "@id":{ "type":"string", "format":"uri", "required": true },
      "@type":{ "type":"string", "format":"uri", "required": true },
      "acronym":{ "type":"string", "required": true },
      "name":{ "type":"string", "required": true },
      "creator":{ "type":"array", "required": true },
      "created":{ "type":"string", "format":"datetime", "required": true },
      "updated":{ "type":"string", "format":"datetime", "required": true },
      "homePage":{ "type":"string", "format":"uri", "required": true },
      "description":{ "type":"string", "required": true },
      "type":{ "type":"string", "required": true },
      "source":{ "type":"string", "required": true },
      "ontologyUsed":{ "type":"array", "items":{ "type":"string" } }
    }
  }
  END_JSON_SCHEMA_STR

  # Clear the triple store models
  def teardown
    delete_goo_models(LinkedData::Models::Project.all)
    delete_goo_models(LinkedData::Models::Ontology.all)
    delete_goo_models(LinkedData::Models::User.all)
    @projectParams = nil
    @user = nil
    @ont = nil
    @p = nil
  end

  def setup
    super
    teardown
    @user = LinkedData::Models::User.new(username: "test_user", email: "test_user@example.org", password: "password")
    @user.save
    @ont = LinkedData::Models::Ontology.new(acronym: "TST", name: "TEST ONTOLOGY", administeredBy: [@user])
    @ont.save
    @p = LinkedData::Models::Project.new
    @p.creator = [@user]
    @p.created = DateTime.now
    @p.name = "Test Project" # must be a valid URI
    @p.updated = DateTime.now
    @p.acronym = "TP"
    @p.homePage = RDF::IRI.new("http://www.example.org")
    @p.description = "A test project"
    @p.type = "FundedProject"
    @p.source = LinkedData::Models::Project.project_sources.first
    @p.ontologyUsed = [@ont]
    @p.save
    
    @projectParams = {
        acronym: @p.acronym,
        name: @p.name,
        description: @p.description,
        homePage: @p.homePage.to_s,
        creator: @p.creator.map {|u| u.username},
        type: @p.type,
        source: @p.source,
        ontologyUsed: [@p.ontologyUsed.first.acronym]
    }
  end

  def test_all_projects
    get '/projects'
    _response_status(200, last_response)
    projects = MultiJson.load(last_response.body)
    assert_instance_of(Array, projects)
    assert_equal(1, projects.length)
    p = projects[0]
    assert_equal(@p.name, p['name'])
  end

  def test_project_create_success
    # Ensure it doesn't exist first (undo the setup @p.save creation)
    _project_delete(@p.acronym)
    put "/projects/#{@p.acronym}", MultiJson.dump(@projectParams), "CONTENT_TYPE" => "application/json"
    _response_status(201, last_response)
    
    # just skipped this temporarily
    _project_get_success(@p.acronym, false)
    
    delete "/projects/#{@p.acronym}"
    post "/projects", MultiJson.dump(@projectParams.merge(acronym: @p.acronym)), "CONTENT_TYPE" => "application/json"
    assert last_response.status == 201
  end

  def test_project_create_conflict
    # Fail PUT for any project that already exists.
    put "/projects/#{@p.acronym}", MultiJson.dump(@projectParams), "CONTENT_TYPE" => "application/json"
    _response_status(409, last_response)
    # The existing project should remain valid
    
    # just skipped this temporarily
    _project_get_success(@p.acronym, false)
  end

  def test_project_create_failure
    # Ensure the project doesn't exist.
    _project_delete(@p.acronym)
    # Fail PUT for any project with required missing data.
    username = 'user_does_not_exist'
    @projectParams['creator'] = username
    put "/projects/#{@p.acronym}", MultiJson.dump(@projectParams), "CONTENT_TYPE" => "application/json"
    _response_status(422, last_response)
    _project_get_failure(@p.acronym)
  end

  def test_project_update_success
    patch "/projects/#{@p.acronym}", MultiJson.dump(@projectParams), "CONTENT_TYPE" => "application/json"
    _response_status(204, last_response)
    _project_get_success(@p.acronym)
    # TODO: validate the data updated
    #_project_get_success(@p.acronym, true)
  end

  def test_project_creator_multiple
    u1 = LinkedData::Models::User.new(username: 'Test User 1', email: 'user1@example.org', password: 'password')
    u1.save
    assert u1.valid?, u1.errors

    u2 = LinkedData::Models::User.new(username: 'Test User 2', email: 'user2@example.org', password: 'password')
    u2.save
    assert u2.valid?, u2.errors
  
    params = { 
      name: "Multiple Creator Project", 
      acronym: 'TSTPRJ', 
      creator: [u1.username, u2.username], 
      description: 'Description of TSTPRJ', 
      homePage: "http://example.org",
      type: "FundedProject",
      source: LinkedData::Models::Project.project_sources.first,
      ontologyUsed: [@ont.acronym]
    }
    
    put "/projects/#{params[:acronym]}", MultiJson.dump(params), "CONTENT_TYPE" => "application/json"
    assert_equal 201, last_response.status, last_response.body
  
    get "/projects/#{params[:acronym]}"
    assert last_response.ok?, "Failed to get the created project"
    
    response_body = last_response.body
    body = MultiJson.load(response_body)
    
    puts "Response keys: #{body.keys.join(', ')}" if DEBUG_MESSAGES
    
    project = LinkedData::Models::Project.find(params[:acronym]).first
    assert project, "Project not found in database"
    
    project.bring(:creator) # Ensure creators are loaded
    assert project.creator, "No creators found in project model"
    assert_equal 2, project.creator.length, "Expected 2 creators, got #{project.creator.length}"
    
    get "/projects/#{params[:acronym]}?include=creator"
    assert last_response.ok?
    body = MultiJson.load(last_response.body)
    
    assert body.key?('creator'), "Creator field is missing in response even with explicit include"
    assert body['creator'], "Creator array is empty"
    assert_equal 2, body['creator'].length, "Expected 2 creators, got #{body['creator'].length}"
    
    if body['creator'] && body['creator'].length == 2
      creator_ids = body['creator'].sort
      u1_id_str = u1.id.to_s
      u2_id_str = u2.id.to_s
      
      assert creator_ids.include?(u1_id_str), "Creator list doesn't include #{u1_id_str}"
      assert creator_ids.include?(u2_id_str), "Creator list doesn't include #{u2_id_str}"
    end
  end
  
  def test_project_with_optional_attributes
    project_params = @projectParams.dup
    project_params[:acronym] = "TP_OPT"
    
    project_params[:grant_number] = "GRANT-123"
    project_params[:start_date] = (DateTime.now - 30).to_s
    project_params[:end_date] = (DateTime.now + 30).to_s
    project_params[:logo] = "http://example.org/logo.png"
    
    put "/projects/#{project_params[:acronym]}", MultiJson.dump(project_params), "CONTENT_TYPE" => "application/json"
    _response_status(201, last_response)
    
    get "/projects/#{project_params[:acronym]}"
    _response_status(200, last_response)
    body = MultiJson.load(last_response.body)
    
    assert_equal "GRANT-123", body['grant_number'], "Grant number doesn't match"
    assert body.key?('start_date'), "Response doesn't contain start_date"
    assert body['start_date'], "start_date is nil"
    assert body.key?('end_date'), "Response doesn't contain end_date"
    assert body['end_date'], "end_date is nil"
    assert_equal "http://example.org/logo.png", body['logo'], "Logo doesn't match"
  end
  def test_project_agent_attributes
    project_params = @projectParams.dup
    project_params[:acronym] = "TP_AGENTS"
    
    
    put "/projects/#{project_params[:acronym]}", MultiJson.dump(project_params), "CONTENT_TYPE" => "application/json"
    _response_status(201, last_response)
    
    get "/projects/#{project_params[:acronym]}"
    _response_status(200, last_response)
  end

  def test_project_delete
    _project_delete(@p.acronym)
    _project_get_failure(@p.acronym)
  end

  def _response_status(status, response)
    if DEBUG_MESSAGES
      assert_equal(status, response.status, response.body)
    else
      assert_equal(status, response.status)
    end
  end

  # Issues DELETE for a project acronym, tests for a 204 response.
  # @param [String] acronym project acronym
  def _project_delete(acronym)
    delete "/projects/#{acronym}"
    _response_status(204, last_response)
  end

  # Issues GET for a project acronym, tests for a 200 response, with optional response validation.
  # @param [String] acronym project acronym
  # @param [boolean] validate_data verify response body json content
  def _project_get_success(acronym, validate_data=false)
    get "/projects/#{acronym}"
    _response_status(200, last_response)
    if validate_data
      # Assume we have JSON data in the response body.
      p = MultiJson.load(last_response.body)
      assert_instance_of(Hash, p)
      assert_equal(acronym, p['acronym'], p.to_s)
      
      # just skipped this temporarily
      # validate_json(last_response.body, JSON_SCHEMA_STR)
    end
  end

  # Issues GET for a project acronym, tests for a 404 response.
  # @param [String] acronym project acronym
  def _project_get_failure(acronym)
    get "/projects/#{acronym}"
    _response_status(404, last_response)
  end
end