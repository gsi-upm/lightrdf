module RDF
  class Repository
    include MonitorMixin
    include Parser  
  
    def initialize options={}
      super()
      
      #debug
      debug = false
      # Assigns the default value to the options.
      @options = {:host=>"http://localhost", :port=>8080, :repository=>"memory", :format=>:ntriples, :complete=>"openrdf-sesame/repositories"}.merge(options)
    end
    
    # Extracts the data in sesame from the indicated repositories
    def data *contexts
      synchronize do
        params = ("?" + contexts.flatten.map{|context| "context=%3C#{CGI::escape(context)}%3E"}*"&&" if !contexts.empty?)

        # Prepares the URL to request the data
        url = "#{repository_statements_url(@options[:repository])}#{params}"

        # Asks for the data
        ntriples = RestClient.get url, :content_type=>content_type

        # Builds the graph
        Parser.parse :rdf, ntriples
      end
	 	end

	  # Gets the list of the sesame contexts
    def contexts
      synchronize do
        # The URL to get the context list from sesame
        url = "#{repository_url(@options[:repository])}/contexts"

        # Asks for the context list and parses it
        Nokogiri::XML( RestClient.get(url, :content_type=>'application/sparql-results+xml') ).search(:uri).map(&:text)
      end
    end

    # Adds data to sesame without removing the previous data
    def data= *args
      synchronize do
        # Retrieve arguments
        graph, context = if args.first.is_a?(Array)
            [args.first.first, args.first.last]
          else
            [args.first, nil]
          end
        
        # Prepares the dir to connect with the repository
        url  = "#{repository_statements_url(@options[:repository])}"
        url += "?context=%3C#{CGI::escape(context)}%3E" if context
        
        # For some reason, sesame doesn't like rdfxml
        sesame_data =  graph.serialize :ntriples
	
        # Sesame:
        begin
          RestClient.post url, sesame_data, :content_type=>content_type
        rescue
          puts "Exception posting to sesame" if debug
        end
	    
        # OMR:
        omr_data = graph.serialize :rdf
	      omrurl= omr_url
	      
        request = RestClient::Request.new(:method => :post, :url => omrurl, :user => @options[:omr_user], :password => @options[:omr_pass], :payload=> omr_data, :verify_ssl => false)

        # Adds the data to OMR
        begin
        	response = request.execute
          puts "Data Added!" if debug
        rescue
          puts "Badrequest" if debug
        end
      end
    end
    
    # Performs a query based on turtle syntax and assuming ?q as variable
    def query string
      query = ""
      RDF::ID.ns.each do |prefix, uri|
        query += "PREFIX #{prefix}: <#{uri}>\n"
      end
      query += "SELECT ?q\n"
      query += "WHERE {#{string}}"
      
      results = sparql(query)
      results.children.first.children[3].children.select { |result| !result.text? }.map do |result|
        node = result.children[1].children[1]
        case node.name.to_sym
        when :uri then
          Node(node.content)
        when :bnode then
          Node("_:#{node.content}")
        when :literal then
          node.content
        end        
      end
    end

    # Performs a SPARQL query
    def sparql query
      synchronize do
        url = "#{repository_url(@options[:repository])}?query=#{CGI::escape(query)}"
        Nokogiri::XML( RestClient.get(url, :content_type=>'application/sparql-results+xml') )
      end
    end

    protected

    # Selects the type of data to send to sesame
    def content_type
      case @options[:format].to_sym
        when :rdfxml  then 'application/rdf+xml'
        when :rdf      then 'application/rdf+xml'
        when :ntriples then 'text/plain'
        when :turtle   then 'application/x-turtle'
        when :n3      then 'text/rdf+n3'
        when :trix    then 'application/trix'
        when :trig     then 'application/x-trig'
      end
    end
    
    def repositories_url
      "#{@options[:host]}:#{@options[:port]}/#{@options[:complete]}"
    end
    
    def omr_url
      "#{@options[:omr_host]}:#{@options[:omr_port]}/#{@options[:omr_complete]}/"
    end
    
    def repository_url repository
      "#{repositories_url}/#{repository}"
    end
    
    def repository_statements_url repository
      "#{repository_url(repository)}/statements"
    end
  end
end
