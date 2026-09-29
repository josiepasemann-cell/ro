import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _bldg_coral import *


class Config(Coral):
    name = "CoralBarrier"
    stage = 1
