module Babylon
  module Base
    
    # Your application's controller should be descendant of this class.
    
    class Controller
      
      attr_accessor :stanza # Stanza received by the controller (Nokogiri::XML::Node)
      
      # Creates a new controller (you should not override this class) and assigns the stanza
      def initialize(params = {})
        params.each do |key, value|
          instance_variable_set("@#{key}", value)
        end
        @rendered = false
      end
      
      # Performs the action and calls back the optional block argument : you should not override this function
      def perform(action, &block)
        @action_name = action
        @block = block
        begin
          self.send(@action_name)
        rescue
          Babylon.logger.error("#{$!}:\n#{$!.backtrace.join("\n")}")
        end
        self.render
      end
      
      # Called by default after each action to "build" a XMPP stanza. By default, it will use the /controller_name/action.xml.builder
      def render(options = nil)
        return if @rendered # Avoid double rendering
        
        if options.nil? # default rendering
          return render(:file => default_template_name)
        elsif action_name = options[:action]
          return render(:file => default_template_name(action_name.to_s))
        end
        render_for_file(File.join("app/views", "#{self.class.name.gsub("Controller","").downcase}", options[:file])) 
        
        # And finally, we set up rendered to be true 
        @rendered = true
      end
      
      protected

      # Used to transfer the assigned variables from the controller to the views
      def hashed_variables
        vars =  Hash.new
         instance_variables.each do |var|
          vars[var[1..-1]] = instance_variable_get(var)
        end
        return vars
      end
      
      # Default template name used to build stanzas
      def default_template_name(action_name = nil)
        path = "#{action_name || @action_name}.xml.builder"
        return path
      end
      
      # Creates the view and "evaluates" it to build the XML for the stanza
      def render_for_file(file)
        Babylon.logger.info("RENDERING : #{file}")
        view = Babylon::Base::View.new(file, hashed_variables)
        @block.call(view.evaluate)
      end
    end
  end
end