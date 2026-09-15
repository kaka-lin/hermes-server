#!/usr/bin/env ruby
# frozen_string_literal: true

# The distributable config uses OpenAI API for its primary and auxiliary calls,
# with an explicit Codex backend only as its fallback route.
require "yaml"

config = YAML.load_file(File.expand_path("../config.example.yaml", __dir__))

raise "main provider is not openai-api" unless config.dig("model", "provider") == "openai-api"
raise "main base URL is not api.openai.com" unless config.dig("model", "base_url") == "https://api.openai.com/v1"
raise "fallback provider is not openai-codex" unless config.dig("fallback_model", "provider") == "openai-codex"
raise "fallback base URL is not the Codex backend" unless config.dig("fallback_model", "base_url") == "https://chatgpt.com/backend-api/codex"

def find_codex_routes(value, path = [])
  case value
  when Hash
    provider = value["provider"].to_s
    base_url = value["base_url"].to_s
    return [path.join(".")] if provider == "openai-codex" || base_url.include?("chatgpt.com/backend-api/codex")

    value.flat_map { |key, child| find_codex_routes(child, path + [key]) }
  when Array
    value.flat_map.with_index { |child, index| find_codex_routes(child, path + [index]) }
  else
    []
  end
end

routes = find_codex_routes({ "model" => config["model"], "auxiliary" => config["auxiliary"] })
raise "Codex route outside fallback_model: #{routes.join(', ')}" unless routes.empty?

puts "OpenAI primary / Codex fallback routes: OK"
