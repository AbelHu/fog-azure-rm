module Fog
  module Storage
    class AzureRM
      # This class provides the actual implemention for service calls.
      class Real
        def set_blob_properties(container_name, name, options = {})
          Fog::Logger.debug "Set Blob #{name} properties #{options.inspect} in container #{container_name}."
          begin
              @blob_client.set_blob_properties(container_name, name, options)
              Fog::Logger.debug "Setting properties of blob #{name} successfully."
              true
            rescue Azure::Core::Http::HTTPError => ex
              raise "Exception in setting properties of blob #{name}: #{ex.inspect}"
            end
        end
      end
      # This class provides the mock implementation for unit tests.
      class Mock
        def set_blob_properties(container_name, name, options = {})
          Fog::Logger.debug "Set Blob #{name} properties #{options.inpsect} in a container #{container_name} successfully."
          true
        end
      end
    end
  end
end
