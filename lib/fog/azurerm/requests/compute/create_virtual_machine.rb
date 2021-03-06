require 'base64'
WHITE_SPACE = ' '.freeze

module Fog
  module Compute
    class AzureRM
      # This class provides the actual implementation for service calls.
      class Real
        def create_virtual_machine(vm_hash)
          msg = "Creating Virtual Machine #{vm_hash[:name]} in Resource Group #{vm_hash[:resource_group]}."
          Fog::Logger.debug msg
          virtual_machine = Azure::ARM::Compute::Models::VirtualMachine.new

          unless vm_hash[:availability_set_id].nil?
            sub_resource = MsRestAzure::SubResource.new
            sub_resource.id = vm_hash[:availability_set_id]
            virtual_machine.availability_set = sub_resource
          end

          string_data = vm_hash[:custom_data]
          string_data = WHITE_SPACE if string_data.nil?
          encoded_data = Base64.strict_encode64(string_data)
          virtual_machine.hardware_profile = define_hardware_profile(vm_hash[:vm_size])
          virtual_machine.storage_profile = define_storage_profile(vm_hash[:name],
                                                                   vm_hash[:storage_account_name],
                                                                   vm_hash[:publisher],
                                                                   vm_hash[:offer],
                                                                   vm_hash[:sku],
                                                                   vm_hash[:version],
                                                                   vm_hash[:vhd_path],
                                                                   vm_hash[:platform],
                                                                   vm_hash[:resource_group])

          virtual_machine.os_profile = if vm_hash[:platform].casecmp(WINDOWS).zero?
                                         define_windows_os_profile(vm_hash[:name],
                                                                   vm_hash[:username],
                                                                   vm_hash[:password],
                                                                   vm_hash[:provision_vm_agent],
                                                                   vm_hash[:enable_automatic_updates],
                                                                   encoded_data)
                                       else
                                         define_linux_os_profile(vm_hash[:name],
                                                                 vm_hash[:username],
                                                                 vm_hash[:password],
                                                                 vm_hash[:disable_password_authentication],
                                                                 vm_hash[:ssh_key_path],
                                                                 vm_hash[:ssh_key_data],
                                                                 encoded_data)
                                       end
          virtual_machine.network_profile = define_network_profile(vm_hash[:network_interface_card_id])
          virtual_machine.location = vm_hash[:location]
          begin
            vm = @compute_mgmt_client.virtual_machines.create_or_update(vm_hash[:resource_group], vm_hash[:name], virtual_machine)
          rescue MsRestAzure::AzureOperationError => e
            raise_azure_exception(e, msg)
          end
          Fog::Logger.debug "Virtual Machine #{vm_hash[:name]} Created Successfully."
          vm
        end

        private

        def define_hardware_profile(vm_size)
          hw_profile = Azure::ARM::Compute::Models::HardwareProfile.new
          hw_profile.vm_size = vm_size
          hw_profile
        end

        def image_reference(publisher, offer, sku, version)
          image_reference = Azure::ARM::Compute::Models::ImageReference.new
          image_reference.publisher = publisher
          image_reference.offer = offer
          image_reference.sku = sku
          image_reference.version = version
          image_reference
        end

        def define_storage_profile(vm_name, storage_account_name, publisher, offer, sku, version, vhd_path, platform, resource_group)
          storage_profile = Azure::ARM::Compute::Models::StorageProfile.new
          os_disk = Azure::ARM::Compute::Models::OSDisk.new
          vhd = Azure::ARM::Compute::Models::VirtualHardDisk.new

          vhd.uri = get_blob_link(storage_account_name) + "/vhds/#{vm_name}_os_disk.vhd"

          if vhd_path.nil?
            storage_profile.image_reference = image_reference(publisher, offer, sku, version)
          else
            # Copy if VHD does not exist belongs to same storage account.
            vhd_storage_account = (vhd_path.split('/')[2]).split('.')[0]
            if storage_account_name != vhd_storage_account
              storage_account = @storage_service.storage_accounts.get(resource_group, storage_account_name)
              access_key = storage_account.get_access_keys.first.value
              storage_data = Fog::Storage::AzureRM.new(provider: 'AzureRM', azure_storage_account_name: storage_account_name, azure_storage_access_key: access_key)
              new_time = get_time
              container_name = "customvhd#{new_time}"
              blob_name = "vhd_image#{new_time}.vhd"
              storage_data.directories.create(
                key: container_name
              )

              storage_data.copy_blob_from_uri(container_name, blob_name, vhd_path)
              until storage_data.get_blob_properties(container_name, blob_name).properties[:copy_status] == 'success'
                Fog::Logger.debug 'Waiting disk to ready'
                sleep(10)
              end
              new_vhd_path = get_blob_link(storage_account_name) + "/#{container_name}/#{blob_name}"
              Fog::Logger.debug "Path:#{new_vhd_path}. | Copy done"
            else
              new_vhd_path = vhd_path
            end

            img_vhd = Azure::ARM::Compute::Models::VirtualHardDisk.new
            img_vhd.uri = new_vhd_path
            os_disk.image = img_vhd
            os_disk.os_type = platform
          end

          os_disk.name = "#{vm_name}_os_disk"
          os_disk.vhd = vhd
          os_disk.create_option = Azure::ARM::Compute::Models::DiskCreateOptionTypes::FromImage
          storage_profile.os_disk = os_disk
          storage_profile
        end

        def define_windows_os_profile(vm_name, username, password, provision_vm_agent, enable_automatic_updates, encoded_data)
          os_profile = Azure::ARM::Compute::Models::OSProfile.new
          windows_config = Azure::ARM::Compute::Models::WindowsConfiguration.new
          windows_config.provision_vmagent = provision_vm_agent
          windows_config.enable_automatic_updates = enable_automatic_updates

          os_profile.windows_configuration = windows_config
          os_profile.computer_name = vm_name
          os_profile.admin_username = username
          os_profile.admin_password = password
          os_profile.custom_data = encoded_data
          os_profile
        end

        def define_linux_os_profile(vm_name, username, password, disable_password_authentication, ssh_key_path, ssh_key_data, encoded_data)
          os_profile = Azure::ARM::Compute::Models::OSProfile.new
          linux_config = Azure::ARM::Compute::Models::LinuxConfiguration.new

          unless ssh_key_path.nil? || ssh_key_data.nil?
            ssh_config = Azure::ARM::Compute::Models::SshConfiguration.new
            ssh_public_key = Azure::ARM::Compute::Models::SshPublicKey.new
            ssh_public_key.path = ssh_key_path
            ssh_public_key.key_data = ssh_key_data
            ssh_config.public_keys = [ssh_public_key]
            linux_config.ssh = ssh_config
          end

          linux_config.disable_password_authentication = disable_password_authentication
          os_profile.linux_configuration = linux_config
          os_profile.computer_name = vm_name
          os_profile.admin_username = username
          os_profile.admin_password = password
          os_profile.custom_data = encoded_data
          os_profile
        end

        def define_network_profile(network_interface_card_id)
          network_profile = Azure::ARM::Compute::Models::NetworkProfile.new
          nic = Azure::ARM::Compute::Models::NetworkInterfaceReference .new
          nic.id = network_interface_card_id
          network_profile.network_interfaces = [nic]
          network_profile
        end
      end
      # This class provides the mock implementation for unit tests.
      class Mock
        def create_virtual_machine(*)
          vm = {
            'location' => 'westus',
            'id' => '/subscriptions/########-####-####-####-############/resourceGroups/fog-test-rg/providers/Microsoft.Compute/virtualMachines/fog-test-server',
            'name' => 'fog-test-server',
            'type' => 'Microsoft.Compute/virtualMachines',
            'properties' =>
            {
              'hardwareProfile' =>
                {
                  'vmSize' => 'Standard_A0'
                },
              'storageProfile' =>
                {
                  'imageReference' =>
                    {
                      'publisher' => 'MicrosoftWindowsServerEssentials',
                      'offer' => 'WindowsServerEssentials',
                      'sku' => 'WindowsServerEssentials',
                      'version' => 'latest'
                    },
                  'osDisk' =>
                    {
                      'name' => 'fog-test-server_os_disk',
                      'vhd' =>
                        {
                          'uri' => 'http://mystorage1.blob.core.windows.net/vhds/fog-test-server_os_disk.vhd'
                        },
                      'createOption' => 'FromImage',
                      'osType' => 'Linux',
                      'caching' => 'ReadWrite'
                    },
                  'dataDisks' => []
                },
              'osProfile' =>
                {
                  'computerName' => 'fog-test-server',
                  'adminUsername' => 'fog',
                  'linuxConfiguration' =>
                    {
                      'disablePasswordAuthentication' => true
                    },
                  'secrets' => [],
                  'customData' => 'ZWNobyBjdXN0b21EYXRh'
                },
              'networkProfile' =>
                {
                  'networkInterfaces' =>
                    [
                      {
                        'id' => '/subscriptions/########-####-####-####-############/resourceGroups/fog-test-rg/providers/Microsoft.Network/networkInterfaces/fog-test-vnet'
                      }
                    ]
                },
              'provisioningState' => 'Succeeded'
            }
          }
          vm_mapper = Azure::ARM::Compute::Models::VirtualMachine.mapper
          @compute_mgmt_client.deserialize(vm_mapper, vm, 'result.body')
        end
      end
    end
  end
end
