require 'gcal4ruby/event'

module GCal4Ruby
#The Calendar Class is the representation of a Google Calendar.  Each user account 
#can have multiple calendars.  You must have an authenticated Service object before 
#using the Calendar object.
#=Usage
#All usages assume a successfully authenticated Service.
#1. Create a new Calendar
#    cal = Calendar.new(service)
#
#2. Find an existing Calendar
#    cal = Calendar.find(service, "New Calendar", :first)
#
#3. Find all calendars containing the search term
#    cal = Calendar.find(service, "Soccer Team")
#
#4. Find a calendar by ID
#    cal = Calendar.find(service, id, :first)
#
#After a calendar object has been created or loaded, you can change any of the 
#attributes like you would any other object.  Be sure to save the calendar to write changes
#to the Google Calendar service.

  class Calendar
  
    GOOGLE_PARAM_NAMES = {
      :mode => "mode",
      :height => "height",
      :width => "width",
      :bg_color => "bgcolor",
      :color => "color",
      :show_title => "showTitle",
      :show_nav => "showNav",
      :show_date => "showDate",
      :show_print => "showPrint",
      :show_tabs => "showTabs",
      :show_calendars => "showCalendars",
      :show_timezone => "showTimezone"    
    }
  
    IFRAME_DEFAULTS = {
      :mode => "WEEK", 
      :height => "600",
      :width => "600",
      :bg_color => "#FFFFFF",
      :color => "#2852A3",
      :show_title => false,
      :show_nav => true,
      :show_date => true,
      :show_print => true,
      :show_tabs => true,
      :show_calendars => true,
      :show_timezone => true
    }
    
    CALENDAR_FEED = "http://www.google.com/calendar/feeds/default/owncalendars/full"
  
    attr_accessor :title, :summary, :hidden, :timezone, :color, :where, :selected
    attr_reader :service, :id, :event_feed, :editable
  
    def initialize(service, attributes = {})
      super()
      @service = service
      attributes.each do |key, value|
        self.send("#{key}=", value)
      end  
    
      # @xml ||= CALENDAR_XML
      #     @exists = false
      #     @title ||= ""
      #     @summary ||= ""
      #     @public ||= false
      #     @hidden ||= false
      #     @timezone ||= "America/Los_Angeles"
      #     @color ||= "#2952A3"
      #     @where ||= ""
      #     return true
    end
  
    #Returns true if the calendar exists on the Google Calendar system (i.e. was 
    #loaded or has been saved).  Otherwise returns false.
    def exists?
      return @exists
    end
  
    #Returns true if the calendar is publically accessable, otherwise returns false.
    def public?
      return @public
    end
  
    #Returns an array of Event objects corresponding to each event in the calendar.
    def events
      events = []
      ret = @service.send_get(@event_feed)
      REXML::Document.new(ret.body).root.elements.each("entry"){}.map do |entry|
        entry.attributes["xmlns:gCal"] = "http://schemas.google.com/gCal/2005"
        entry.attributes["xmlns:gd"] = "http://schemas.google.com/g/2005"
        entry.attributes["xmlns:app"] = "http://www.w3.org/2007/app"
        entry.attributes["xmlns"] = "http://www.w3.org/2005/Atom"
        entry.attributes["xmlns:georss"] = "http://www.georss.org/georss"
        entry.attributes["xmlns:gml"] = "http://www.opengis.net/gml"
        e = Event.new(self)
        if e.load(entry.to_s)
          events << e
        end
      end
      return events
    end
  
    #Set the calendar to public (p = true) or private (p = false).  Publically viewable
    #calendars can be accessed by anyone without having to log in to google calendar.  See
    #Calendar#to_iframe for options to display a public calendar in a webpage.
    def public=(p)
      if p
        permissions = 'http://schemas.google.com/gCal/2005#read' 
      else
        permissions = 'none'
      end
    
      #if p != @public
        path = "http://www.google.com/calendar/feeds/#{@id}/acl/full/default"
        request = REXML::Document.new(ACL_XML)
        request.root.elements.each() do |ele|
          if ele.name == 'role'
            ele.attributes['value'] = permissions
          end
        
        end
        if @service.send_put(path, request.to_s, {"Content-Type" => "application/atom+xml", "Content-Length" => request.length.to_s})
          @public = p
          return true
        else
          return false
        end
      #end
    end


  
    #Deletes a calendar.  If successful, returns true, otherwise false.  If successful, the
    #calendar object is cleared.
    def delete
      if @exists    
        if @service.send_delete(CALENDAR_FEED+"/"+@id)
          @exists = false
          @title = nil
          @summary = nil
          @public = false
          @id = nil
          @hidden = false
          @timezone = nil
          @color = nil
          @where = nil
          return true
        else
          return false
        end
      else
        return false
      end
    end
  
    #If the calendar does not exist, creates it, otherwise updates the calendar info.  Returns
    #true if the save is successful, otherwise false.
    def save
      if @exists
        ret = service.send_put(@edit_feed, to_xml(), {'Content-Type' => 'application/atom+xml'})
      else
        ret = service.send_post(CALENDAR_FEED, to_xml(), {'Content-Type' => 'application/atom+xml'})
      end
      if !@exists
        if load(ret.read_body)
          return true
        else
          raise CalendarSaveFailed
        end
      end
      return true
    end
  
    #Class method for querying the google service for specific calendars.  The service parameter
    #should be an appropriately authenticated Service. The term parameter can be any string.  The
    #scope parameter may be either :all to return an array of matches, or :first to return 
    #the first match as a Calendar object.
    def self.find(service, query_term=nil, params = {})
      t = query_term.downcase if query_term
      cals = service.calendars
      ret = []
      cals.each do |cal|
        title = cal.title || ""
        summary = cal.summary || ""
        id = cal.id || ""
        if id == query_term
          return cal
        end
        if title.downcase.match(t) or summary.downcase.match(t)
          if params[:scope] == :first
            return cal
          else
            ret << cal
          end
        end
      end
      ret
    end
  
    def self.get(service, id)
      url = 'http://www.google.com/calendar/feeds/default/allcalendars/full/'+id
      ret = service.send_get(url)
      puts "==return=="
      puts ret.body
    end
  
    def self.query(service, query_term)
      url = 'http://www.google.com/calendar/feeds/default/allcalendars/full'+"?q="+CGI.escape(query_term)
      ret = service.send_get(url)
      puts "==return=="
      puts ret.body
    end
  
    #Reloads the calendar objects information from the stored server version.  Returns true
    #if successful, otherwise returns false.  Any information not saved will be overwritten.
    def reload
      if not @exists
        return false
      end  
      t = Calendar.find(service, @id, :first)
      if t
        load(t.to_xml)
      else
        return false
      end
    end
  
    #Returns the xml representation of the Calenar.
    def to_xml
      xml = REXML::Document.new(@xml)
      xml.root.elements.each(){}.map do |ele|
        case ele.name
        when "title"
          ele.text = @title
        when "summary"
          ele.text = @summary
        when "timezone"
          ele.attributes["value"] = @timezone
        when "hidden"
          ele.attributes["value"] = @hidden.to_s
        when "color"
          ele.attributes["value"] = @color
        when "selected"
          ele.attributes["value"] = @selected.to_s
        end
      end
      xml.to_s
    end

    #Loads the Calendar with returned data from Google Calendar feed.  Returns true if successful.
    def load(string)
      @exists = true
      @xml = string
      xml = REXML::Document.new(string)
      xml.root.elements.each(){}.map do |ele|
        case ele.name
          when "id"
            @id = ele.text.gsub("http://www.google.com/calendar/feeds/default/calendars/", "")
          when 'title'
            @title = ele.text
          when 'summary'
            @summary = ele.text
          when "color"
            @color = ele.attributes['value']
          when 'hidden'
            @hidden = ele.attributes["value"] == "true" ? true : false
          when 'timezone'
            @timezone = ele.attributes["value"]
          when "selected"
            @selected = ele.attributes["value"] == "true" ? true : false
          when "link"
            if ele.attributes['rel'] == 'edit'
              @edit_feed = ele.attributes['href']
            end
        end
      end
    
      @event_feed = "http://www.google.com/calendar/feeds/#{@id}/private/full"
    
      if @service.check_public
        puts "Getting ACL Feed" if @service.debug
      
        #rescue error on shared calenar ACL list access
        begin 
          ret = @service.send_get("http://www.google.com/calendar/feeds/#{@id}/acl/full/")
        rescue Exception => e
          @public = false
          @editable = false
          return true
        end
        @editable = true
        r = REXML::Document.new(ret.read_body)
        r.root.elements.each("entry") do |ele|
          ele.elements.each do |e|
            #puts "e = "+e.to_s if @service.debug
            #puts "previous element = "+e.previous_element.to_s if @service.debug
            #added per eruder http://github.com/h13ronim/gcal4ruby/commit/3074ebde33bd3970500f6de992a66c0a4578062a
            if e.name == 'role' and e.previous_element and e.previous_element.name == 'scope' and e.previous_element.attributes['type'] == 'default'
              if e.attributes['value'].match('#read')
                @public = true
              else
                @public = false
              end
            end
          end
        end
      else
        @public = false
        @editable = true
      end
      return true
    end
  
    def to_iframe(params = {})
      raise "The calendar must exist and be saved before you can use this method." unless self.id
      GCal4Ruby::Calendar.to_iframe(self.id, params)
    end
  
    def self.to_iframe(id, params = {})
      raise "Calendar ID is required" unless id
      options = build_options_set(params)
      url_options = options.join("&amp;")
      "<iframe src='http://www.google.com/calendar/embed?src=#{id}&amp;#{output}' width='#{options[:width]}' height='#{options[:height]}' frameborder='0' scrolling='no'></iframe>"  
    end

  private
  
    def build_options_set(params)
      IFRAME_DEFAULTS.merge(params).collect do |key, value|
        if IFRAME_DEFAULTS.keys.include?(key)
          [GOOGLE_PARAM_NAMES[key], raw_value_to_param_value(value)].join("=")
        end
      end
    end
  
    def raw_value_to_param_value(value)
      case value
        when true then "1"
        when false then "0"
        else value
      end
    end
  
  end 
end