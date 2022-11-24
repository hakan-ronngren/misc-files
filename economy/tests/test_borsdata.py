import os
import time
import requests

from unittest import TestCase
from unittest.mock import MagicMock, PropertyMock

from borsdata import borsdata as api
from borsdata import config


originals = dict()
originals['requests.get'] = requests.get
originals['api.read_from_json_file'] = api.read_from_json_file
originals['api.write_to_json_file'] = api.write_to_json_file
originals['os.path.isfile'] = os.path.isfile
originals['os.path.getmtime'] = os.path.getmtime
originals['config.data_directory'] = config.data_directory
originals['config.config'] = config.config


class FakeRequest:
    def __init__(self, status_code, json):
        self.status_code = status_code
        self._json = json

    def json(self):
        return self._json


class TestBorsdata(TestCase):
    def setUp(self):
        requests.get = MagicMock(side_effect=Exception('requests.get must be mocked'))
        api.read_from_json_file = MagicMock(side_effect=Exception('api.read_from_json_file must be mocked'))
        api.write_to_json_file = MagicMock(side_effect=Exception('api.write_to_json_file must be mocked'))
        os.path.isfile = MagicMock(side_effect=Exception('os.path.isfile must be mocked'))
        os.path.getmtime = MagicMock(side_effect=Exception('os.path.getmtime must be mocked'))
        config.data_directory = MagicMock(return_value='/path/to/data/directory')
        config.config = MagicMock(return_value={'api_key': 'xxx'})

    def tearDown(self):
        requests.get = originals['requests.get']
        api.read_from_json_file = originals['api.read_from_json_file']
        api.write_to_json_file = originals['api.write_to_json_file']
        os.path.isfile = originals['os.path.isfile']
        os.path.getmtime = originals['os.path.getmtime']
        config.data_directory = originals['config.data_directory']
        config.config = originals['config.config']

    def test_call_api_and_write_cache_when_cache_file_does_not_exist(self):
        requests.get = MagicMock(return_value=FakeRequest(200, [{"foo": "bar"}]))
        os.path.isfile = MagicMock(return_value=False)
        api.write_to_json_file = MagicMock(return_value=None)

        actual = api.get_data('/api/path', 10)
        expected = [{'foo': 'bar'}]

        self.assertSequenceEqual(expected, actual)
        requests.get.assert_called_once_with('https://apiservice.borsdata.se/api/path?authKey=xxx')
        api.write_to_json_file.assert_called_once()

    def test_read_cache_file_when_fresh(self):
        os.path.isfile = MagicMock(return_value=True)
        os.path.getmtime = MagicMock(return_value=time.time())
        api.read_from_json_file = MagicMock(return_value=[{"foo": "bar"}])

        actual = api.get_data('/api/path', 10)
        expected = [{'foo': 'bar'}]

        self.assertSequenceEqual(expected, actual)
        api.write_to_json_file.assert_not_called()

    def test_call_api_and_write_cache_when_cache_file_is_obsolete(self):
        requests.get = MagicMock(return_value=FakeRequest(200, [{"foo": "bar"}]))
        os.path.isfile = MagicMock(return_value=True)
        os.path.getmtime = MagicMock(return_value=0)
        api.write_to_json_file = MagicMock(return_value=None)

        actual = api.get_data('/api/path', 10)
        expected = [{'foo': 'bar'}]

        self.assertSequenceEqual(expected, actual)
        requests.get.assert_called_once_with('https://apiservice.borsdata.se/api/path?authKey=xxx')
        api.write_to_json_file.assert_called_once()
