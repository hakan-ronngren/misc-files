import borsdata.instrument

class InstrumentStatistics:
    def __init__(self, instr: borsdata.instrument.Instrument):
        self.instr = instr

    def average(self):
        return sum(d.closing_price for d in self.instr.days) / len(self.instr.days)
