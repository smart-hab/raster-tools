import smart_hab.clip as _clip
import smart_hab.convert_shape as _convert_shape
import smart_hab.mask as _mask
import smart_hab.norm_diff as _norm_diff
import smart_hab.png as _png
import smart_hab.select_bands as _select_bands

def clip():
  args = _clip.parse_args()
  _clip.main(args)

def convert_shape():
  args = _convert_shape.parse_args()
  _convert_shape.main(args)

def mask():
  args = _mask.parse_args()
  _mask.main(args)

def png():
  args = _png.parse_args()
  _png.main(args)

def norm_diff():
  args = _norm_diff.parse_args()
  _norm_diff.main(args)

def select_bands():
  args = _select_bands.parse_args()
  _select_bands.main(args)
