# frozen_string_literal: true

require "yaml"

module Slidict
  MethodSlide = Struct.new(:title, :role, :instructions, keyword_init: true)

  class PresentationMethod
    REQUIRED_FIELDS = %w[id name category description suitable_for slides ai_instructions review_checklist].freeze
    REQUIRED_SLIDE_FIELDS = %w[title role instructions].freeze

    attr_reader :id, :name, :category, :description, :suitable_for, :slides,
                :ai_instructions, :review_checklist, :references, :locale, :source_path

    def initialize(attributes, source_path: nil)
      @source_path = source_path
      @id = attributes.fetch("id")
      @name = attributes.fetch("name")
      @category = attributes.fetch("category")
      @description = attributes.fetch("description")
      @suitable_for = Array(attributes.fetch("suitable_for"))
      @slides = Array(attributes.fetch("slides")).map do |slide|
        MethodSlide.new(
          title: slide.fetch("title"),
          role: slide.fetch("role"),
          instructions: slide.fetch("instructions")
        )
      end
      @ai_instructions = Array(attributes.fetch("ai_instructions"))
      @review_checklist = Array(attributes.fetch("review_checklist"))
      @references = Array(attributes["references"])
      @locale = attributes.fetch("locale", "en")
    end

    def self.load_file(path)
      attributes = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
      validate!(attributes, path)
      new(attributes, source_path: path)
    rescue Psych::Exception, KeyError, TypeError => e
      raise ArgumentError, "invalid presentation method #{path}: #{e.message}"
    end

    def self.validate!(attributes, path)
      raise ArgumentError, "#{path} must contain a YAML mapping" unless attributes.is_a?(Hash)

      missing = REQUIRED_FIELDS.reject { |field| present?(attributes[field]) }
      raise ArgumentError, "#{path} is missing required fields: #{missing.join(', ')}" unless missing.empty?

      unless attributes["id"].is_a?(String) && attributes["id"].match?(/\A[a-z0-9-]+\z/)
        raise ArgumentError, "#{path} id must be a string using lowercase letters, numbers, and hyphens"
      end
      raise ArgumentError, "#{path} slides must be a non-empty array" unless attributes["slides"].is_a?(Array) && !attributes["slides"].empty?

      attributes["slides"].each_with_index do |slide, index|
        unless slide.is_a?(Hash)
          raise ArgumentError, "#{path} slide #{index + 1} must be a mapping"
        end

        missing_slide = REQUIRED_SLIDE_FIELDS.reject { |field| present?(slide[field]) }
        next if missing_slide.empty?

        raise ArgumentError, "#{path} slide #{index + 1} is missing required fields: #{missing_slide.join(', ')}"
      end
    end

    def self.present?(value)
      case value
      when String then !value.strip.empty?
      when Array then !value.empty?
      else !value.nil?
      end
    end
  end

  class PresentationMethodRegistry
    BUILTIN_GLOB = File.expand_path("../../data/slidict/methods/*.yml", __dir__)
    PLUGIN_GLOB = "slidict/methods/*.yml"

    def initialize(paths: nil, include_plugins: true)
      @paths = paths || default_paths(include_plugins: include_plugins)
    end

    def all
      @all ||= @paths.sort.map { |path| PresentationMethod.load_file(path) }.sort_by(&:id)
    end

    def find(id)
      all.find { |method| method.id == id.to_s }
    end

    def fetch(id)
      find(id) || raise(ArgumentError, "unknown presentation method #{id}")
    end

    private

    def default_paths(include_plugins:)
      paths = Dir[BUILTIN_GLOB]
      paths += Gem.find_files(PLUGIN_GLOB) if include_plugins
      paths.uniq
    end
  end
end
