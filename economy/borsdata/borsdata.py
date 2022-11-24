import json
import os
import requests
import time

from typing import List

from . import config


'''Borsdata API wrapper'''


# TODO: decide where to have this one. We had it in an outer module in Ruby.
def is_offline() -> bool:
    return False


def read_from_json_file(path: str):
    with open(path, 'r') as f:
        return json.load(f)


def write_to_json_file(path: str, data) -> None:
    with open(path, 'w') as f:
        f.write(json.dumps(data))


def get_data(path: str, max_age_seconds: int) -> dict:
    '''
    Returns the JSON response for a specific URL path, using a cache.

    Args:
        path (str): URL path to call
        max_age_seconds (int): maximum age of cache file
    '''
    api_host = 'apiservice.borsdata.se'
    cache_file = os.path.join(config.data_directory(), f'cache/{path}.json')
    data = None
    if os.path.isfile(cache_file) and (is_offline() or time.time() - os.path.getmtime(cache_file) < 1000 * max_age_seconds):
        print(f"reading {path} from cache")
        data = read_from_json_file(cache_file)
    elif not is_offline():
        print(f"asking api for {path}")
        uri = f'https://{api_host}{path}?authKey={config.config()["api_key"]}'
        response = requests.get(uri)
        # Throttle (max 100 requests per 10 seconds)
        time.sleep(0.1)
        if response.status_code == 200:
            data = response.json()
            print(f"writing {path} to cache")
            write_to_json_file(cache_file, data)
    return data


class LazyInstantiator:
    '''Lazily instantiates a class from dicts in a list upon request, indexes them and makes them available.'''

    def __init__(self, dicts, cls, keys: List[str]) -> 'LazyInstantiator':
        '''
        Args:
            dicts (List[Dict]): A list of dicts from which instances can be created
            cls (Class): The class to instantiate, the constructor of which must take a dict as the only argument
            keys (List[str]): The dict keys to index on. There must be no two objects having the same value for any of these keys.
        '''
        self.dicts = dicts
        self.cls = cls
        self.indices = dict()
        for index_name in keys:
            self.indices[index_name] = dict()

    def get(self, key, value):
        '''Returns the instance that corresponds to the key/value, always the same one.'''
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
