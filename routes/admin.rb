require 'sinatra'
require 'zip'

config_options = JSON.parse(File.read('./config.json'))

######
# Admin Interfaces
######

get '/admin/' do
    redirect to("/no_access") if not is_administrator?
    @admin = true

    haml :admin, :encode_html => true
end

get '/admin/add_user' do
    redirect to("/no_access") if not is_administrator?

    @admin = true

    haml :add_user, :encode_html => true
end

# serve a copy of the code
get '/admin/pull' do
    redirect to("/no_access") if not is_administrator?

	if File.exists?("./export.zip")
		send_file "./export.zip", :filename => "export.zip", :type => 'Application/octet-stream'
	else
		"No copy of the code available. Run scripts/make_export.sh."
	end
end

#create DB backup
get '/admin/dbbackup' do
	redirect to("/no_access") if not is_administrator?
  bdate  = Time.now()
  filename = "./tmp/master" + "-" + (bdate.strftime("%Y%m%d%H%M%S") +".bak")
	FileUtils::copy_file("./db/master.db", filename)
  if not File.zero?(filename)
    	send_file filename, :filename => "#{filename}", :type => 'Application/octet-stream'
  else
    	"No copy of the database is available. Please try again."
    	sleep(5)
    	redirect to("/admin/")
	end
end

#create backup of all attachments
get '/admin/attacments_backup' do
  bdate  = Time.now()
  zip_file = "./tmp/Attachments" + "-" + (bdate.strftime("%Y%m%d%H%M%S") +".zip")
  Zip::File.open(zip_file, Zip::File::CREATE) do |zipfile|
    Dir["./attachments/*" ].each do | name|
      zipfile.add(name.split("/").last,name)
    end
  end
  send_file zip_file, :type => 'zip', :filename => zip_file
  #File.delete(rand_zip) should the temp file be deleted?
end

# Create a new user
post '/admin/add_user' do
    redirect to("/no_access") if not is_administrator?

    user = User.first(:username => params[:username])

    if user
        if params[:password] and params[:password].size > 1
            # we have to hardcode the input params to prevent param pollution
            user.update(:type => params[:type], :auth_type => params[:auth_type], :password => params[:password])
        else
            # we have to hardcode the params to prevent param pollution
            user.update(:type => params[:type], :auth_type => params[:auth_type])
        end
    else
        user = User.new
        user.username = params[:username]
        user.password = params[:password]
        user.type = params[:type]
        user.auth_type = params[:auth_type]
        user.save
    end

    redirect to('/admin/list_user')
end

get '/admin/list_user' do
    redirect to("/no_access") if not is_administrator?
    @admin = true
    @users = User.all

    haml :list_user, :encode_html => true
end

get '/admin/edit_user/:id' do
    redirect to("/no_access") if not is_administrator?

    @user = User.first(:id => params[:id])

    haml :add_user, :encode_html => true
end

get '/admin/delete/:id' do
    redirect to("/no_access") if not is_administrator?

    @user = User.first(:id => params[:id])
    @user.destroy if @user

    redirect to('/admin/list_user')
end

get '/admin/add_user/:id' do
    if not is_administrator?
        id = params[:id]
        unless get_report(id)
            redirect to("/no_access")
        end
    end

    @users = User.all(:order => [:username.asc])
    @report = Reports.first(:id => params[:id])

    if is_administrator?
      @admin = true
    end

    haml :add_user_report, :encode_html => true
end

post '/admin/add_user/:id' do
    if not is_administrator?
        id = params[:id]
        unless get_report(id)
            redirect to("/no_access")
        end
    end

    report = Reports.first(:id => params[:id])

    if report == nil
        return "No Such Report"
    end

    authors = report.authors

    if authors
        authors = authors.push(params[:author])
    else
        authors = ["#{params[:author]}"]
    end

    report.authors = authors
    report.save

    redirect to("/reports/list")
end

get '/admin/del_user_report/:id/:author' do
    if not is_administrator?
        id = params[:id]
        unless get_report(id)
            redirect to("/no_access")
        end
    end

    report = Reports.first(:id => params[:id])

    if report == nil
        return "No Such Report"
    end

    authors = report.authors

    if authors
        authors = authors - ["#{params[:author]}"]
    end

    report.authors = authors
    report.save

    redirect to("/reports/list")
end

get '/admin/config' do
    redirect to("/no_access") if not is_administrator?

    @config = config_options
    if config_options["cvss"]
        @scoring = "cvss"
    elsif config_options["dread"]
        @scoring = "dread"
    else
        @scoring = "default"
    end

    haml :config, :encode_html => true
end

post '/admin/config' do
    redirect to("/no_access") if not is_administrator?

    ft = params["finding_types"].split(",")
    udv = params["user_defined_variables"].split(",")

    config_options["finding_types"] = ft
    config_options["user_defined_variables"] = udv
    config_options["port"] = params["port"]
    config_options["use_ssl"] = params["use_ssl"] ? true : false
    config_options["bind_address"] = params["bind_address"]
    config_options["ldap"] = params["ldap"] ? true : false
    config_options["ldap_domain"] = params["ldap_domain"]
    config_options["ldap_dc"] = params["ldap_dc"]
    config_options["burpmap"] = params["burpmap"] ? true : false
    config_options["nessusmap"] = params["nessusmap"] ? true : false
    config_options["vulnmap"] = params["vulnmap"] ? true : false
    config_options["logo"] = params["logo"]
    config_options["auto_import"] = params["auto_import"] ? true : false
    config_options["chart"] = params["chart"] ? true : false
    config_options["threshold"] = params["threshold"]
    config_options["show_exceptions"] = params["show_exceptions"] ? true : false

    if params["risk_scoring"] == "CVSS"
        config_options["dread"] = false
        config_options["cvss"] = true
    elsif params["risk_scoring"] == "DREAD"
        config_options["dread"] = true
        config_options["cvss"] = false
    else
        config_options["dread"] = false
        config_options["cvss"] = false
    end

    File.open("./config.json","w") do |f|
      f.write(JSON.pretty_generate(config_options))
    end
    redirect to("/admin/config")
end

# get plugins available
get '/admin/plugins' do
    redirect to("/no_access") if not is_administrator?

    @plugins = []
    Dir[File.join(File.dirname(__FILE__), "../plugins/**/", "*.json")].each { |lib|
        @plugins.push(JSON.parse(File.open(lib).read))
    }

    haml :plugins, :encode_html => true
end

# enable plugins
post '/admin/plugins' do
    redirect to("/no_access") if not is_administrator?

    @plugins = []
    Dir[File.join(File.dirname(__FILE__), "../plugins/**/", "*.json")].each { |lib|
        @plugins.push(JSON.parse(File.open(lib).read))
    }

    @plugins.each do |plug|
        p params
        if params[plug["name"]]
            plug["enabled"] = true
            File.open("./plugins/#{plug['name']}/plugin.json","w") do |f|
              f.write(JSON.pretty_generate(plug))
            end
        else
            plug["enabled"] = false
            File.open("./plugins/#{plug['name']}/plugin.json","w") do |f|
              f.write(JSON.pretty_generate(plug))
            end
        end
    end

    redirect to("/admin/plugins")
end


# Manage Templated Reports
get '/admin/templates' do
    redirect to("/no_access") if not is_administrator?

    @admin = true

    # Query for all Findings
    @templates = Xslt.all(:order => [:report_type.asc])

    haml :template_list, :encode_html => true
end

# Manage Templated Reports
get '/admin/templates/add' do
    redirect to("/no_access") if not is_administrator?

    @admin = true

    haml :add_template, :encode_html => true
end

# Manage Templated Reports
get '/admin/templates/:id/download' do
    redirect to("/no_access") if not is_administrator?

    @admin = true

    xslt = Xslt.first(:id => params[:id])

    send_file xslt.docx_location, :type => 'docx', :filename => "#{xslt.report_type}.docx"
end

get '/admin/delete/templates/:id' do
    redirect to("/no_access") if not is_administrator?

    @xslt = Xslt.first(:id => params[:id])

	if @xslt
		@xslt.destroy
		File.delete(@xslt.xslt_location)
		File.delete(@xslt.docx_location)
	end
    redirect to('/admin/templates')
end


# Manage Templated Reports
post '/admin/templates/add' do
    redirect to("/no_access") if not is_administrator?

    @admin = true

	xslt_file = "./templates/#{rand(36**36).to_s(36)}.xslt"

    redirect to("/admin/templates/add") unless params[:file]

	# reject if the file is above a certain limit
	if params[:file][:tempfile].size > 100000000
		return "File too large. 10MB limit"
	end

	docx = "./templates/#{rand(36**36).to_s(36)}.docx"
	File.open(docx, 'wb') {|f| f.write(params[:file][:tempfile].read) }

    error = false
    detail = ""
    begin
	    xslt = generate_xslt(docx)
    rescue ReportingError => detail
        error = true
    end


    if error
        "The report template you uploaded threw an error when parsing:<p><p> #{detail.errorString}"
    else

    	# open up a file handle and write the attachment
	    File.open(xslt_file, 'wb') {|f| f.write(xslt) }

	    # delete the file data from the attachment
	    datax = Hash.new
	    # to prevent traversal we hardcode this
	    datax["docx_location"] = "#{docx}"
	    datax["xslt_location"] = "#{xslt_file}"
	    datax["description"] = 	params[:description]
	    datax["report_type"] = params[:report_type]
	    data = url_escape_hash(datax)
	    data["finding_template"] = params[:finding_template] ? true : false
	    data["status_template"] = params[:status_template] ? true : false

	    @current = Xslt.first(:report_type => data["report_type"])

	    if @current
		    @current.update(:xslt_location => data["xslt_location"], :docx_location => data["docx_location"], :description => data["description"])
	    else
		    @template = Xslt.new(data)
		    @template.save
	    end

	    redirect to("/admin/templates")

        haml :add_template, :encode_html => true
    end
end

# Manage Templated Reports
get '/admin/templates/:id/edit' do
    redirect to("/no_access") if not is_administrator?

    @admind = true
    @template = Xslt.first(:id => params[:id])

    haml :edit_template, :encode_html => true
end

# Manage Templated Reports
post '/admin/templates/edit' do
    redirect to("/no_access") if not is_administrator?

    @admin = true
    template = Xslt.first(:id => params[:id])

    xslt_file = template.xslt_location

    redirect to("/admin/templates/#{params[:id]}/edit") unless params[:file]

    # reject if the file is above a certain limit
    if params[:file][:tempfile].size > 100000000
        return "File too large. 10MB limit"
    end

    docx = "./templates/#{rand(36**36).to_s(36)}.docx"
    File.open(docx, 'wb') {|f| f.write(params[:file][:tempfile].read) }

    error = false
    detail = ""
    begin
	    xslt = generate_xslt(docx)
    rescue ReportingError => detail
        error = true
    end

    if error
        "The report template you uploaded threw an error when parsing:<p><p> #{detail.errorString}"
    else

    	# open up a file handle and write the attachment
	    File.open(xslt_file, 'wb') {|f| f.write(xslt) }

	    # delete the file data from the attachment
	    datax = Hash.new
	    # to prevent traversal we hardcode this
	    datax["docx_location"] = "#{docx}"
	    datax["xslt_location"] = "#{xslt_file}"
	    datax["description"] = 	params[:description]
	    datax["report_type"] = params[:report_type]
	    data = url_escape_hash(datax)
	    data["finding_template"] = params[:finding_template] ? true : false
	    data["status_template"] = params[:status_template] ? true : false

	    @current = Xslt.first(:report_type => data["report_type"])

	    if @current
		    @current.update(:xslt_location => data["xslt_location"], :docx_location => data["docx_location"], :description => data["description"])
	    else
		    @template = Xslt.new(data)
		    @template.save
	    end

	    redirect to("/admin/templates")
    end
end

# get enabled plugins
get '/admin/admin_plugins' do
    @menu = []
    Dir[File.join(File.dirname(__FILE__), "../plugins/**/", "*.json")].each { |lib|
        pl = JSON.parse(File.open(lib).read)
        a = {}
        if pl["enabled"] and pl["admin_view"]
            # add the plugin to the menu
            a["name"] = pl["name"]
            a["description"] = pl["description"]
            a["link"] = pl["link"]
            @menu.push(a)
        end
    }
    haml :enabled_plugins, :encode_html => true
end

