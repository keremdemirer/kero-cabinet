# frozen_string_literal: true
require 'sketchup.rb'
require 'extensions.rb'

module KeroCabinet
  unless file_loaded?(__FILE__)
    extension = SketchupExtension.new('Kero Cabinet', 'kero_cabinet/core')
    extension.description = 'Parametric cabinetry: casework, face frames, doors, shelves and drawer boxes.'
    extension.version = '0.22.1'
    extension.creator = 'Kero Cabinet'
    Sketchup.register_extension(extension, true)
    file_loaded(__FILE__)
  end
end
