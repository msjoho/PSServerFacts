# Sample Chef client config
node_name        'srv01.prod.example.com'
chef_server_url  "https://chef.example.com/organizations/myorg"
environment      'prod'
validation_client_name 'myorg-validator'
log_level        :info
log_location     'C:/chef/log/client.log'
# Comment line that should be ignored
