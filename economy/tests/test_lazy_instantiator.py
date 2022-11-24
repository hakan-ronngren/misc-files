import os
import time
import requests

from unittest import TestCase  # , skip
from unittest.mock import MagicMock, PropertyMock

from borsdata import borsdata as api
from borsdata import config


class TestLazyInstantiator(TestCase):
    def setUp(self):
        self.data_for_john = {'id': 1, 'name': 'John', 'email': 'John@example.com'}
        self.data_for_kate = {'id': 2, 'name': 'Kate', 'email': 'Kate@example.com'}
        self.cut = api.LazyInstantiator(
            [self.data_for_john, self.data_for_kate],
            DictTestObject,
            ['id', 'email'])

    def test_lookup_by_first_index(self):
        data = self.data_for_kate
        obj = self.cut.get('id', data['id'])

        self.assertListEqual([data['name'], data['email']], [obj.name, obj.email])

    def test_lookup_by_other_index(self):
        data = self.data_for_john
        obj = self.cut.get('email', data['email'])

        self.assertListEqual([data['name'], data['email']], [obj.name, obj.email])

    def test_objects_are_singletons(self):
        data = self.data_for_kate
        obj_by_id = self.cut.get('id', data['id'])
        obj_by_email = self.cut.get('email', data['email'])

        self.assertEqual(obj_by_id, obj_by_email)

    def test_returns_none_if_no_match(self):
        obj = self.cut.get('id', 999)
        self.assertIsNone(obj)


class DictTestObject:
    def __init__(self, data):
        self.name = data['name']
        self.email = data['email']

# class DictTestObject:
#     def __init__(self, data):
#         self._data = data

#     @property
#     def name(self):
#         return self._data['name']

#     @property
#     def email(self):
#         return self._data['email']
