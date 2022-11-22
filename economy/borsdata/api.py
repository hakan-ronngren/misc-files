import json
import os
import requests
import time

from .config import config
from .config import root_directory


# TODO: decide where to have this one. We had it in an outer module in Ruby.
def is_offline() -> bool:
    return False

def get_data(path: str, max_age_seconds: int) -> dict:
    api_host = 'apiservice.borsdata.se'
    cache_file = os.path.join(root_directory(), f'cache/{path}.json')
    data = None
    if os.path.isfile(cache_file) and (is_offline() or time.time() - os.path.getmtime(cache_file) < 1000 * max_age_seconds):
        print(f"reading {path} from cache")
        with open(cache_file, 'r') as f:
            data = json.load(f)
    elif not is_offline():
        print(f"asking api for {path}")
        uri = f'https://{api_host}{path}?authKey={config()["api_key"]}'
        response = requests.get(uri)
        # Throttle (max 100 requests per 10 seconds)
        time.sleep(0.1)
        if response.status_code == 200:
            data = response.json()
            print(f"writing {path} to cache")
            with open(cache_file, 'w') as f:
                f.write(json.dumps(data))
    return data

def get_by_id(id: int,
              clazz):
    obj = clazz.memory_cache.get(id)
    if obj is None:
        for item in get_data(clazz.api_path, clazz.max_disk_cache_age_seconds)[clazz.response_key]:
            if item[clazz.id_key] == id:
                obj = clazz(item)
        clazz.memory_cache[id] = obj

    return obj

