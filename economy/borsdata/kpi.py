from . import borsdata as api


class KPI:
    DIVIDEND_ID = 7

    def __init__(self, item):
        '''
        Metadata object for all KPIs

        ```python
        from borsdata import kpi
        for item in kpi._get_dicts():
            print('{0}: {1}'.format(item['kpiId'], item['nameEn']))

        1: Dividend Yield
        2: P/E
        3: P/S
        4: P/B
        5: Revenue/share
        6: Earnings/share
        7: Dividend
        8: Book value/share
        9: P/(E)x
        10: EV/EBIT
        # ...
        # ...
        ...
        ```
        '''
        self.name = item['nameEn']

    @classmethod
    def get_by_id(cls, oid: int) -> 'KPI':
        return _instantiator.get('kpiId', oid)


def _get_dicts():
    return api.get_data('/v1/instruments/kpis/metadata', 86400)['kpiHistoryMetadatas']


_instantiator = api.LazyInstantiator(_get_dicts, KPI, ['kpiId'])
