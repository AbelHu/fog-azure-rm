module Fog
  module Network
    class AzureRM
      # Real class for Network Request
      class Real
        def list_network_interfaces(resource_group)
          Fog::Logger.debug "Getting list of NetworkInterfaces from Resource Group #{resource_group}."
          begin
            network_interfaces = @network_client.network_interfaces.list_as_lazy(resource_group)
            network_interfaces.next_link = '' if network_interfaces.next_link.nil?
            network_interfaces.value
          rescue  MsRestAzure::AzureOperationError => e
            raise_azure_exception(e, "Getting list of NetworkInterfaces from Resource Group #{resource_group}")
          end
        end
      end

      # Mock class for Network Request
      class Mock
        def list_network_interfaces(resource_group)
          nic = {
              'value' => [
              {
                'id' => "/subscriptions/########-####-####-####-############/resourceGroups/#{resource_group}/providers/Microsoft.Network/networkInterfaces/test-NIC",
                'name' => 'test-NIC',
                'type' => 'Microsoft.Network/networkInterfaces',
                'location' => 'westus',
                'properties' =>
                  {
                    'ipConfigurations' =>
                      [
                        {
                          'id' => "/subscriptions/########-####-####-####-############/resourceGroups/#{resource_group}/providers/Microsoft.Network/networkInterfaces/test-NIC/ipConfigurations/ipconfig1",
                          'properties' =>
                            {
                              'privateIPAddress' => '10.2.0.4',
                              'privateIPAllocationMethod' => 'Dynamic',
                              'subnet' =>
                                 {
                                   'id' => "/subscriptions/########-####-####-####-############/resourceGroups/#{resource_group}/providers/Microsoft.Network/virtualNetworks/testVnet/subnets/fog-test-subnet"
                                 },
                              'provisioningState' => 'Succeeded'
                            },
                          'name' => 'ipconfig1'
                        }
                      ],
                    'dnsSettings' =>
                      {
                        'dnsServers' => [],
                        'appliedDnsServers' => []
                      },
                    'enableIPForwarding' => false,
                    'resourceGuid' => '51e01337-fb15-4b04-b9de-e91537c764fd',
                    'provisioningState' => 'Succeeded'
                  }
              }
            ]
          }
          network_interface_mapper = Azure::ARM::Network::Models::NetworkInterface.mapper
          @network_client.deserialize(network_interface_mapper, nic, 'result.body')
        end
      end
    end
  end
end
