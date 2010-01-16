require 'rubygems'
require 'httparty'
require 'mash'

class PivotalTracker
  
  include HTTParty
  format :xml
  
  def initialize(api_token, options = {})
    self.class.headers 'X-TrackerToken' => api_token
    use_ssl = options.delete(:ssl)
    self.class.base_uri "http#{'s' if use_ssl}://www.pivotaltracker.com/services/v2"
  end
  
  def get_all_activities
    response = self.class.get("/activities")
    raise_errors(response)
    parse_response(response, 'activities')
  end
  
  def get_all_project_activities(project_id)
    response = self.class.get("/projects/#{project_id}/activities")
    raise_errors(response)
    parse_response(response, 'activities')
  end
  
  def get_all_projects
    response = self.class.get("/projects")
    raise_errors(response)
    parse_response(response, 'projects')
  end
  
  def get_project(project_id)
    response = self.class.get("/projects/#{project_id}")
    raise_errors(response)
    parse_response(response, 'project')
  end
  
  def create_project(name, options = {})
    response = self.class.post('/projects', :body => {:project => options.merge(:name => name)})
    raise_errors(response)
    parse_response(response, 'project')
  end
  
  def get_all_project_memberships(project_id)
    response = self.class.get("/projects/#{project_id}/memberships")
    raise_errors(response)
    parse_response(response, 'memberships')
  end
  
  def get_project_membership(project_id, membership_id)
    response = self.class.get("/projects/#{project_id}/memberships/#{membership_id}")
    raise_errors(response)
    parse_response(response, 'membership')
  end
  
  def add_project_membership(project_id, role, email, options = {})
    response = self.class.post("/projects/#{project_id}/memberships", :body => {:membership => {:role => role, :person => options.merge(:email => email)}})
    raise_errors(response)
    parse_response(response, 'membership')
  end
  
  def remove_project_membership(project_id, membership_id)
    response = self.class.delete("/projects/#{project_id}/memberships/#{membership_id}")
    raise_errors(response)
    parse_response(response, 'membership')
  end
  
  def get_all_project_iterations(project_id)
    response = self.class.get("/projects/#{project_id}/iterations")
    raise_errors(response)
    parse_response(response, 'iterations')
  end
  
  def get_all_project_stories(project_id,query={})
    filter = query.delete(:filter)

    if filter && Hash === filter
      filter = filter.inject([]) {|f,(key,value)| f << "#{key}:#{value}"}.join(' ')
    end

    query[:filter] = URI.escape(filter) if filter

    response = self.class.get("/projects/#{project_id}/stories", :query => query)
    raise_errors(response)
    parse_response(response, 'stories')
  end

  def add_project_story(project_id,story)
    response = self.class.post("/projects/#{project_id}/stories", :body => {:story => story})
    raise_errors(response)
    parse_response(response, 'story')
  end

  # XXX activesupport dependency has crept in... hmm
  def update_project_story(project_id, story_id, story)
    body = story.to_xml(:root => 'story', :skip_instruct => true, :indent => 0).tapp
    headers = self.class.headers.update('Content-Type' => 'application/xml')

    response = self.class.put("/projects/#{project_id}/stories/#{story_id}", :headers => headers, :body => body)
    raise_errors(response)
    parse_response(response, 'story')
  end

  def delete_story(project_id,story_id)
    response = self.class.delete("/projects/#{project_id}/stories/#{story_id}")
    raise_errors(response)
    parse_response(response, 'story')
  end

  def add_note(project_id, story_id, text)
    body = request_xml('note', :text => text).tapp
    
    response = self.class.post("/projects/#{project_id}/stories/#{story_id}/notes", :body => body, :headers => xml_headers)
    raise_errors(response)
    parse_response(response, 'note')
  end
    
  private

    def request_xml(root_tag,tree)
      tree.to_xml(:root => root_tag, :skip_instruct => true, :indent => 0)
    end

    def xml_headers
      self.class.headers.update('Content-Type' => 'application/xml')
    end
  
    def raise_errors(response)
      response.body.tapp

      errors = ''
      errors = response['errors'].inspect if response['errors']

      case response.code.to_i
        when 400
          raise PivotalTracker::BadRequest.new(response), "(#{response.code}): #{response.message} - #{response['message'] if response}"
        when 401
          raise PivotalTracker::Unauthorized.new(response), "(#{response.code}): #{response.message} - #{response.body if response}"
        when 403
          raise PivotalTracker::General, "(#{response.code}): #{response.message}"
        when 404
          raise PivotalTracker::ResourceNotFound, "(#{response.code}): #{response.message}"
        when 422
          raise PivotalTracker::ResourceInvalid, "(#{response.code}): #{response['errors'].inspect if response['errors']}"
        when 500
          raise PivotalTracker::InformPivotal, "Pivotal Tracker had an internal error. Please let them know. (#{response.code}): #{response.message}, #{errors}"
        when 502..503
          raise PivotalTracker::Unavailable, "(#{response.code}): #{response.message}"
      end
    end
    
    # Create Mash objects from response data for the given resource(s)
    def parse_response(response, resource)
      response = cleanup_pivotal_data(response.body)
      data = response[resource]
      if data.is_a?(Array)
        data.collect {|object| Mash.new(object)}
      else
        Mash.new(data)
      end
    end
    
    # Make Crack's XML parsing happy by correctly defining Pivotal's nested collections as arrays
    # This can be removed when all collections returned by Pivotal Tracker's API have the type=array attribute set
    def cleanup_pivotal_data(body)
      %w{ projects memberships iterations stories }.each do |resource|
        body.gsub!("<#{resource}>", "<#{resource} type=\"array\">")
      end
      response = Crack::XML.parse(body)
    end
end

require File.dirname(__FILE__) + '/pivotal_tracker/error'
