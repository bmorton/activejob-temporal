# frozen_string_literal: true

require 'temporalio'
require 'temporalio/client'
require 'temporalio/env_config'

module ActiveJob
  module Temporal
    # Lazily-connected, memoized Temporalio::Client per process.
    # SDK objects cannot cross forks: connect lazily and call #reset! after fork
    # (or ActiveJob::Temporal.reset_client!) so each child reconnects.
    class ClientManager
      def initialize(config)
        @config = config
        @mutex = Mutex.new
        @env_config = nil
      end

      def client
        @mutex.synchronize { @client ||= connect }
      end

      def reset!
        @mutex.synchronize { @client = nil }
      end

      private

      def connect
        options = client_options

        address = @config.address
        namespace = @config.namespace

        if address.nil?
          (address, namespace), env_opts = env_connect_options
          options = env_opts.merge(options) { |_k, env_v, cfg_v| cfg_v.nil? ? env_v : cfg_v }
        end

        Temporalio::Client.connect(address, namespace, **options.compact)
      end

      def client_options
        options = {
          api_key: @config.api_key,
          tls: @config.tls,
          interceptors: @config.interceptors,
          logger: @config.logger,
          lazy_connect: true
        }
        options[:data_converter] = @config.data_converter if @config.data_converter
        options
      end

      # Falls back to Temporalio::EnvConfig (TEMPORAL_ADDRESS, TEMPORAL_NAMESPACE,
      # TEMPORAL_API_KEY, TEMPORAL_TLS_* and TOML profiles) when no explicit
      # address is configured, so the same code targets local dev and Cloud.
      def env_connect_options
        Temporalio::EnvConfig::ClientConfig.load_client_connect_options
      end
    end
  end
end
