require 'fog/core/collection'
require 'fog/azurerm/models/storage/container'

module Fog
  module Storage
    class AzureRM
      # This class is giving implementation of listing containers.
      class Containers < Fog::Collection
        model Fog::Storage::AzureRM::Container

        def all(options = { metadata: true })
          containers = []
          service.list_containers(options).each do |container|
            hash = Container.parse container
            hash['public_access_level'] = 'unknown'
            containers << hash
          end
          load containers
        end

        def get(identity)
          container = all(prefix: identity, metadata: true).find { |item| item.name == identity }
          return if container.nil?

          access_control_list = service.get_container_access_control_list(identity)[0]
          container.public_access_level = if access_control_list.is_a? Hash
                                            access_control_list['public_access_level']
                                          else
                                            access_control_list.public_access_level
                                          end
          container
        end

        def get_container_metadata(name)
          service.get_container_metadata(name)
        end

        def set_container_metadata(name, metadata)
          service.set_container_metadata(name, metadata)
        end
      end
    end
  end
end
