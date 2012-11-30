#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Christopher Brown (<cb@opscode.com>)
# Author:: Nuo Yan (<nuo@opscode.com>)
# Author:: Seth Falcon (<seth@opscode.com>)
# Copyright:: Copyright (c) 2008-2011 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/cookbook_loader'
require 'chef/cookbook_version'

class CookbooksController < ApplicationController

  respond_to :html
  before_filter :require_login
  before_filter :params_helper

  attr_reader :cookbook_id
  def params_helper
    @cookbook_id = params[:id] || params[:cookbook_id]
  end

  def index
    @cl = fetch_cookbook_versions(6)
    respond_with @cl
  end

  def show
    begin
      all_books = fetch_cookbook_versions("all", :cookbook => cookbook_id)
      @versions = all_books[cookbook_id].map { |v| v["version"] }
      if params[:cb_version] == "_latest"
        redirect_to show_specific_version_cookbook_url(cookbook_id, @versions.first)
        return
      end
      @version = params[:cb_version]
      if !@versions.include?(@version)
        msg = { :warning => ["Cookbook #{cookbook_id} (#{params[:cb_version]})",
                             "is not available in the #{session[:environment]}",
                             "environment."
                            ].join(" ") }
        redirect_to cookbooks_url, :flash => msg
        return
      end
      cookbook_url = "cookbooks/#{cookbook_id}/#{@version}"
      @cookbook = client_with_actor.get(cookbook_url)
      raise HTTPStatus::NotFound, "Cannot find cookbook #{cookbook_id} (@version)" unless @cookbook
      @manifest = @cookbook.manifest
      respond_with @cookbook
    rescue => e
      log_and_flash_exception(e)
      @cl = {}
      render :index
    end
  end

  # GET /cookbooks/cookbook_id
  # provides :json, for the javascript on the environments web form.
  def cb_versions
    respond_to :json
    use_envs = session[:environment] && !params[:ignore_environments]
    num_versions = params[:num_versions] || "all"
    all_books = fetch_cookbook_versions(num_versions, :cookbook => cookbook_id,
                                        :use_envs => use_envs)
    respond_with({ cookbook_id => all_books[cookbook_id] })
  end

  def recipe_files
    # node = params.has_key?('node') ? params[:node] : nil
    # @recipe_files = load_all_files(:recipes, node)
    @recipe_files = client_with_actor.get("cookbooks/#{params[:id]}/recipes")
    respond_with @recipe_files
  end

  def attribute_files
    @attribute_files = client_with_actor.get("cookbooks/#{params[:id]}/attributes")
    respond_with @attribute_files
  end

  def definition_files
    @definition_files = client_with_actor.get("cookbooks/#{params[:id]}/definitions")
    respond_with @definition_files
  end

  def library_files
    @lib_files = client_with_actor.get("cookbooks/#{params[:id]}/libraries")
    respond_with @lib_files
  end

  private

  def fetch_cookbook_versions(num_versions, options={})
    opts = { :use_envs => true, :cookbook => nil }.merge(options)
    url = if opts[:use_envs]
            env = session[:environment] || "_default"
            "environments/#{env}/cookbooks"
          else
            "cookbooks"
          end
    # we want to display at most 5 versions, but we ask for 6.  This
    # tells us if we should display a 'show all' button or not.
    url += "/#{opts[:cookbook]}" if opts[:cookbook]
    url += "?num_versions=#{num_versions}"
    begin
      result = client_with_actor.get(url)
      result.inject({}) do |ans, (name, cb)|
        cb["versions"].each do |v|
          v["url"] = show_specific_version_cookbook_url(:cookbook_id => name,
                                                        :cb_version => v["version"])
        end
        ans[name] = cb["versions"]
        ans
      end
    rescue => e
      log_and_flash_exception(e, $!)
      {}
    end
  end

end