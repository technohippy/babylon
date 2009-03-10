module Babylon

  ## 
  # Connection Exception
  class NotConnected < Exception; end

  ##
  # This class is in charge of handling the network connection to the XMPP server.
  class XmppConnection < EventMachine::Connection

    ##
    # Returns the host for connection.
    # Usually it is the configured host, but the children classes can orverride this. The ClientConnection class does it to perform DNS resultion.
    # Also, if a subclass assigns a value to an "port" or "host" attribute, they will be used.
    def host
      @host || Babylon.config['host']
    end
    
    ##
    # Returns the port for connection
    def port
      @host || Babylon.config['port']
    end

    ##
    # Connects the XmppConnection to the right host with the right port. 
    # It passes itself (as handler) and the configuration
    def self.connect(params, &block)
      Babylon.logger.debug("CONNECTING TO #{host}:#{port}") # Very low level Logging
      EventMachine::connect(host, port, self, params.merge({:on_connection => block}))
    end
    
    def connection_completed
      Babylon.logger.debug("CONNECTED") # Very low level Logging
    end

    ##
    # Called when the connection is terminated and stops the event loop
    def unbind()
      Babylon.logger.debug("DISCONNECTED") # Very low level Logging
      EventMachine::stop_event_loop
    end

    ## 
    # Instantiate the Handler (called internally by EventMachine) and attaches a new XmppParser
    def initialize(params)
      super()
      @stanza_callback = params[:on_stanza]
      @connection_callback = params[:on_connection]
      @parser = XmppParser.new(&method(:receive_stanza))
    end

    ##
    # Called when a full stanza has been received and returns it to the central router to be sent to the corresponding controller.
    def receive_stanza(stanza)
      # If not handled by subclass (for authentication)
      @stanza_callback.call(stanza) if @stanza_callback
    end
    
    ## 
    # Sends the Nokogiri::XML data (after converting to string) on the stream. It also appends the right "from" to be the component's JId if none has been mentionned. Eventually it displays this data for debugging purposes.
    # This method also adds a "from" attribute to all stanza if it was ommited (the full jid) only if a "to" attribute is present. if not, we assume that we're speaking to the server and the server doesn't need a "from" to identify where the message is coming from.
    def send(xml)
      if xml.is_a? Nokogiri::XML::NodeSet
        xml.each do |node|
          node["from"] = jid if !node.attributes["from"] && node.attributes["to"]
        end
      elsif xml.is_a? Nokogiri::XML::Node
        xml["from"] = jid if !xml.attributes["from"] && xml.attributes["to"]
      end
      Babylon.logger.debug("SENDING #{xml}")
      send_data "#{xml}"
    end
    
    ##
    # Memoizer for jid. The jid can actually be changed in subclasses (client will probbaly want to change it to include the resource) 
    def jid
      @jid ||= Babylon.config['jid']
    end

    private

    ## 
    # receive_data is called when data is received. It is then passed to the parser. 
    def receive_data(data)
      Babylon.logger.debug("RECEIVED #{data}")
      @parser.parse data
    end
  end

  ##
  # This is the XML SAX Parser that accepts "pushed" content
  class XmppParser < Nokogiri::XML::SAX::Document
    
    ##
    # Initialize the parser and adds the callback that will be called upen stanza completion
    def initialize(&callback)
      @callback = callback
      super()
      @parser = Nokogiri::XML::SAX::Parser.new(self)
      @doc = nil
      @elem = nil
    end
    
    ##
    # Parses the received data
    def parse(data)
      @parser.parse data
    end

    ## 
    # Called when the document received in the stream is started
    def start_document
      @doc = Nokogiri::XML::Document.new
    end
    
    ##
    # Adds characters to the current element (being parsed)
    def characters(string)
      @elem.add_child(Nokogiri::XML::Text.new(string, @doc))
    end

    ##
    # Instantiate a new current Element, adds the corresponding attributes and namespaces
    # The new element is eventually added to a parent element (if present).
    # If this element is the first element (the root of the document), then instead of adding it to a parent, we add it to the document itself. In this case, the current element will not be terminated, so we activate the callback immediately.
    def start_element(qname, attributes = [])
      e = Nokogiri::XML::Element.new(qname, @doc)
      add_namespaces_and_attributes_to_node(attributes, e)
      
      # If we don't have any elem yet, we are at the root
      @elem = @elem ? @elem.add_child(e) : (@root = e)
      
      if @elem.name == "stream:stream"
        # Should be called only for stream:stream
        @doc = Nokogiri::XML::Document.new
        @root = @elem
        @doc.root = @elem
        @callback.call(@elem)
      end
    end

    ##
    # Terminates the current element and calls the callback
    def end_element(name)
      if @elem
        if @elem.parent == @root
          @callback.call(@elem) 
          # And we also need to remove @elem from its tree
          @elem.unlink 
          # And the current elem is the root
          @elem = @root 
        else
          @elem = @elem.parent 
        end
      end
    end
    
    private
    
    ##
    # Adds namespaces and attributes. Nokogiri passes them as a array of [name, value, name, value]...
    def add_namespaces_and_attributes_to_node(attrs, node) 
      (attrs.size / 2).times do |i|
        name, value = attrs[2 * i], attrs[2 * i + 1]
        if name =~ /xmlns/
          node.add_namespace(name, value)
        else
          node.set_attribute name, value
        end
      end
    end
    
  end

end
