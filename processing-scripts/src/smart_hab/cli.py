import smart_hab.clip as clip
import smart_hab.convert_shape as convert_shape
import smart_hab.mask as mask
import smart_hab.norm_diff as norm_diff
import smart_hab.png as png
import smart_hab.select_bands as select_bands

def cli_clip():
  args = clip.parse_args()
  clip.main(args)

def cli_convert_shape():
  args = convert_shape.parse_args()
  convert_shape.main(args)

def cli_mask():
  args = mask.parse_args()
  mask.main(args)

def cli_png():
  args = png.parse_args()
  png.main(args)

def cli_norm_diff():
  args = norm_diff.parse_args()
  norm_diff.main(args)

def cli_select_bands():
  args = select_bands.parse_args()
  select_bands.main(args)
