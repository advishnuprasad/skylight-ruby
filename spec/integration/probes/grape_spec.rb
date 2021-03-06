require 'spec_helper'
require 'skylight/instrumenter'

if defined?(Grape)
  describe 'Grape integration', :grape_probe, :agent do
    include Rack::Test::Methods

    before do
      @called_endpoint = nil
      Skylight::Instrumenter.mock! do |trace|
        @called_endpoint = trace.endpoint
      end
    end

    after do
      Skylight::Instrumenter.stop!
    end

    class GrapeTest < Grape::API
      class App < Grape::API
        get "test" do
          { test: true }
        end

        desc 'Update item' do
          detail 'We take the id to update the item'
          named 'Update route'
        end
        post "update/:id" do
          { update: true }
        end

        namespace :users do
          get :list do
            { users: [] }
          end
        end

        namespace :admin do
          before do
            Skylight.instrument("verifying admin")
          end

          get :secret do
            { admin: true }
          end
        end

        route :any, "*path" do
          { path: params[:path] }
        end
      end

      format :json

      mount App => '/app'

      desc 'This is a test'
      get "test" do
        { test: true }
      end

      get "raise" do
        fail 'Unexpected error'
      end
    end

    def app
      Rack::Builder.new do
        use Skylight::Middleware
        run GrapeTest
      end
    end

    it "creates a Trace for a Grape app" do
      expect(Skylight).to receive(:trace).with("Rack", "app.rack.request").and_call_original

      get "/test"

      expect(@called_endpoint).to eq("GrapeTest [GET] test")
      expect(JSON.parse(last_response.body)).to eq("test" => true)
    end

    it "instruments the endpoint body" do
      Skylight::Trace.any_instance.stub(:instrument)

      expect_any_instance_of(Skylight::Trace).to receive(:instrument)
          .with("app.grape.endpoint", "GET test", nil)
          .once

      get "/test"
    end

    it "instuments mounted apps" do
      Skylight::Trace.any_instance.stub(:instrument)

      expect_any_instance_of(Skylight::Trace).to receive(:instrument)
          .with("app.grape.endpoint", "GET test", nil)
          .once

      get "/app/test"

      expect(@called_endpoint).to eq("GrapeTest::App [GET] test")
    end

    it "instruments more complex endpoints" do
      Skylight::Trace.any_instance.stub(:instrument)

      expect_any_instance_of(Skylight::Trace).to receive(:instrument)
          .with("app.grape.endpoint", "POST update/:id", nil)
          .once

      post "/app/update/1"

      expect(@called_endpoint).to eq("GrapeTest::App [POST] update/:id")
    end

    it "instruments namespaced endpoints" do
      Skylight::Trace.any_instance.stub(:instrument)

      expect_any_instance_of(Skylight::Trace).to receive(:instrument)
          .with("app.grape.endpoint", "GET users list", nil)
          .once

      get "/app/users/list"

      expect(@called_endpoint).to eq("GrapeTest::App [GET] users/list")
    end

    it "instruments wildcard routes" do
      Skylight::Trace.any_instance.stub(:instrument)

      expect_any_instance_of(Skylight::Trace).to receive(:instrument)
          .with("app.grape.endpoint", "any *path", nil)
          .once

      delete "/app/missing"

      expect(@called_endpoint).to eq("GrapeTest::App [any] *path")
    end

    it "instruments failures" do
      Skylight::Trace.any_instance.stub(:instrument)

      expect_any_instance_of(Skylight::Trace).to receive(:instrument)
          .with("app.grape.endpoint", "GET raise", nil)
          .once

      expect{
        get "/raise"
      }.to raise_error("Unexpected error")

      expect(@called_endpoint).to eq("GrapeTest [GET] raise")
    end

    it "instruments filters" do
      Skylight::Trace.any_instance.stub(:instrument)

      # TODO: Attempt to verify order
      expect_any_instance_of(Skylight::Trace).to receive(:instrument)
          .with("app.grape.filters", "Before Filters", nil)
          .once

      expect_any_instance_of(Skylight::Trace).to receive(:instrument)
          .with("app.block", "verifying admin", nil)
          .once

      expect_any_instance_of(Skylight::Trace).to receive(:instrument)
          .with("app.grape.endpoint", "GET admin secret", nil)
          .once

      get "/app/admin/secret"

      expect(@called_endpoint).to eq("GrapeTest::App [GET] admin/secret")
    end

    it "handles detailed descriptions"

    # This happens when a path matches but the method does not
    it "treats 405s correctly"
  end
end
