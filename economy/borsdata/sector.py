from . import api


class Sector:
    memory_cache = dict()
    api_path = '/v1/sectors'
    max_disk_cache_age_seconds = 86400
    response_key = 'sectors'
    id_key = 'id'

    def __init__(self, item):
        self.name = item['name']


_mem_cache = dict()

def get_by_id(id) -> Sector:
    return api.get_by_id(id, Sector)
