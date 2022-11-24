from typing import List

from . import borsdata as api
from .branch import Branch
from .sector import Sector


class InstrumentDay:
    def __init__(self, item) -> 'InstrumentDay':
        self.date = item['d']
        self.highest_price = item['h']
        self.lowest_price = item['l']
        self.closing_price = item['c']
        self.opening_price = item['o']
        self.volume = item['v']


class Instrument:
    def __init__(self, item):
        print(f'building Instrument from {item}')
        self.oid = item['insId']
        self.name = item['name']
        self.ticker = item['ticker']
        self._sector_id = item['sectorId']
        self._branch_id = item['branchId']

    @property
    def branch(self) -> str:
        if not hasattr(self, '_branch'):
            self._branch = Branch.get_by_id(self._branch_id)
        return self._branch

    @property
    def sector(self) -> str:
        if not hasattr(self, '_sector'):
            self._sector = Sector.get_by_id(self._sector_id)
        return self._sector

    @property
    def days(self) -> List[InstrumentDay]:
        if not hasattr(self, '_days'):
            data = api.get_data(f'/v1/instruments/{self.oid}/stockprices', 86400)
            self._days = list(InstrumentDay(item) for item in data['stockPricesList'])
        return self._days

    @classmethod
    def get_by_id(cls, oid: int) -> 'Instrument':
        return _instantiator.get('insId', oid)

    @classmethod
    def get_by_isin(cls, isin: str) -> 'Instrument':
        return _instantiator.get('isin', isin)

    @classmethod
    def get_by_ticker(cls, ticker: str) -> 'Instrument':
        return _instantiator.get('ticker', ticker)


def _get_dicts():
    global _dicts
    if _dicts is None:
        _dicts = api.get_data('/v1/instruments', 86400)['instruments']
    return _dicts


# TODO: Prevent this from running prematurely (can't call the function below, must pass it)
_dicts = None
_instantiator = api.LazyInstantiator(_get_dicts(), Instrument, ['insId', 'isin', 'ticker'])
