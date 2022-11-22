from . import api


class Index:
    '''Indexes a list of objects based on a specific key'''

    def __init__(self, cls, index_key: str) -> 'Index':
        self.cls = cls
        self.index_key = index_key
        self.index = dict()

    def get(self, index_value):
        obj = self.index.get(index_value)
        if obj is None:
            for item in self.cls.all_from_api():
                if item[self.index_key] == index_value:
                    obj = self.cls(item)
            self.index[index_value] = obj

        return obj
