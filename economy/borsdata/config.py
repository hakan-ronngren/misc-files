import os
import yaml


def root_directory() -> str:
    """ Gives the path of, and creates, the root directory for all local configuration and cache """
    root_dir = os.path.expanduser('~/.borsdata-client')
    os.makedirs(root_dir, exist_ok=True)
    return root_dir

def config() -> dict:
    config_file = os.path.join(root_directory(), 'config.yml')

    if not os.path.isfile(config_file):
        with open(config_file, 'w') as f:
            f.write(yaml.safe_dump({'api_key': 'xxx'}))
        print(f'Created config file: {config_file}. Please write your API key there.')

    with open(config_file, 'r') as f:
        data = yaml.safe_load(f)
    return data
