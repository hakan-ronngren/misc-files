#!/usr/bin/env python3

from borsdata import api
from borsdata import instrument

#data = api.get_data('/v1/sectors', 3600)
#print(data)

instr = instrument.get_by_id(999)
print(f'instrument name: {instr.name}')
print(f'ticker: {instr.ticker}')
print(f'sector name: {instr.sector.name}')
print(f'price on {instr.days[3].date}: {instr.days[3].closing_price}')

instr = instrument.get_by_id(999)
print(f'price on {instr.days[3].date}: {instr.days[3].closing_price}')
