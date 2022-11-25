import json
import os
import requests
import time
import urllib.parse

from functools import cached_property
from typing import List

from . import config


# TODO: decide where to have this one. We had it in an outer module in Ruby.
def is_offline() -> bool:
    return False


def read_from_json_file(path: str):
    with open(path, 'r') as f:
        return json.load(f)


def write_to_json_file(path: str, data) -> None:
    containing_directory = os.path.dirname(path)
    os.makedirs(containing_directory, exist_ok=True)
    with open(path, 'w') as f:
        f.write(json.dumps(data))


def get_data(path: str, **url_params) -> dict:
    '''
    Returns the JSON response for a specific URL path, using a cache.

    Args:
        path (str): URL path to call
        url_params (dict): URL parameters to add (will become URI-encoded)
    '''
    max_age_seconds = 86400
    qpath = f'{path}?authKey={config.config()["api_key"]}'
    for k, v in url_params.items():
        qpath = qpath + f'&{k}={urllib.parse.quote(str(v))}'
    api_host = 'apiservice.borsdata.se'
    cache_file = os.path.join(config.data_directory(), f'cache/{path}.json')
    data = None
    if os.path.isfile(cache_file) and (is_offline() or time.time() - os.path.getmtime(cache_file) < 1000 * max_age_seconds):
        # Read {path} from cache
        data = read_from_json_file(cache_file)
    elif not is_offline():
        # Ask api for {path}
        uri = f'https://{api_host}{qpath}'
        print(uri)
        response = requests.get(uri)
        # Throttle (max 100 requests per 10 seconds)
        time.sleep(0.1)
        if response.status_code == 200:
            data = response.json()
            # Write {path} to cache
            write_to_json_file(cache_file, data)
    return data


class LazyInstantiator:
    '''
    Lazily instantiates a class from dicts in a list upon request, indexes them and makes them available.

    You give it a function that will be used to fetch a list of items from the API the first time the get
    method is called. This way you do not need to feed the instantiator with any data upon creation.
    '''

    def __init__(self, fetcher, cls, keys: List[str]) -> 'LazyInstantiator':
        '''
        Args:
            fetcher (function): A function that will fetch a list of dicts from which instances can be created
            cls (class): The class to instantiate, the constructor of which must take a dict as the only argument
            keys (List[str]): The dict keys to index on. There must be no two objects having the same value for any of these keys.
        '''
        self._fetcher = fetcher
        self.cls = cls
        self.indices = dict()
        for index_name in keys:
            self.indices[index_name] = dict()

    @cached_property
    def dicts(self):
        return self._fetcher()

    def get(self, key, value):
        '''Returns the instance that corresponds to the key/value, always the same one.'''
        if self.indices.get(key) is None:
            raise KeyError(f"The LazyInstantiator for {self.cls} does not have an index for '{key}'")
        index = self.indices[key]
        instance = index.get(value)
        if instance is None:
            # Not there, so we must create one and put in all indices
            try:
                data = next(d for d in self.dicts if d[key] == value)
                instance = self.cls(data)
                for index_name, index in self.indices.items():
                    index[data[index_name]] = instance
            except StopIteration:
                # There is no such data dict, so let instance stay None
                pass

        return instance
