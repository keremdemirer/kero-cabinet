# Stand-in for SketchUp's ground-plane face orientation and coordinate transforms.
# Does not constitute a runtime SketchUp test.
$LOADED_FEATURES << 'sketchup.rb'
def file_loaded?(_)
  true
end

Z_AXIS = Object.new
Y_AXIS = Object.new
X_AXIS = Object.new
module Geom
  class Transformation
    attr_reader :origin, :scale
    def initialize(origin = [0,0,0], scale = [1,1,1])
      @origin, @scale = origin, scale
    end
    def self.scaling(x, y, z)
      new([0,0,0], [x,y,z])
    end
    def *(other)
      self.class.new(@origin.zip(other.origin, @scale).map { |a,b,scale| a+b*scale }, @scale.zip(other.scale).map { |a,b| a*b })
    end
    def to_a
      [@scale[0],0,0,0, 0,@scale[1],0,0, 0,0,@scale[2],0, *@origin,1]
    end
  end
end
module Sketchup
  Color = Struct.new(:r, :g, :b)
  def self.active_model
    @active_model
  end
  def self.active_model=(x)
    @active_model = x
  end
end
class MockFace
  attr_reader :extrusion
  def initialize(definition, points)
    @definition = definition
    @points = points
    @axis = points.respond_to?(:normal_axis) ? points.normal_axis : (0..2).find { |axis| points.map { |p| p[axis] }.uniq.length==1 } || 2
    @up = false # SketchUp ground plane faces always initially face down.
  end
  def normal
    self
  end
  def samedirection?(_axis)
    @up
  end
  def reverse!
    @up = !@up
  end
  def pushpull(distance)
    @extrusion = @up ? distance : -distance
    @definition.extrusion = @extrusion
    @definition.points = @points
    vertices = @points + @points.map { |point| copy = point.dup; copy[@axis] += @extrusion; copy }
    low = 3.times.map { |axis| vertices.map { |point| point[axis] }.min }
    high = 3.times.map { |axis| vertices.map { |point| point[axis] }.max }
    @definition.mesh_min = @definition.mesh_min ? @definition.mesh_min.zip(low).map(&:min) : low
    @definition.mesh_max = @definition.mesh_max ? @definition.mesh_max.zip(high).map(&:max) : high
  end
end
class MockEntities
  attr_reader :instances
  def initialize(definition = nil)
    @definition = definition
    @instances = []
  end
  def add_face(points)
    MockFace.new(@definition, points)
  end
  def add_circle(center, _normal, radius, _segments)
    points = [[center[0]-radius,center[1],center[2]],[center[0],center[1],center[2]+radius],
      [center[0]+radius,center[1],center[2]],[center[0],center[1],center[2]-radius]]
    def points.normal_axis; 1; end
    points
  end
  def add_instance(definition, transform)
    obj = MockInstance.new(definition, transform)
    @instances << obj
    obj
  end
end
class MockDef
  attr_accessor :description, :name, :points, :extrusion, :mesh_min, :mesh_max
  attr_reader :entities
  def get_attribute(dict, key)
    (@attributes || {})[[dict,key]]
  end
  def set_attribute(dict, key, value)
    (@attributes ||= {})[[dict,key]] = value
  end
  def initialize(name)
    @name = name
    @entities = MockEntities.new(self)
  end
end
class MockDefinitions
  include Enumerable
  def each(&block)
    @all.each(&block)
  end
  attr_reader :all
  def initialize
    @all = []
  end
  def add(name)
    d = MockDef.new(name)
    @all << d
    d
  end
end
class MockInstance
  def set_attribute(dict, key, value)
    (@attributes ||= {})[[dict,key]] = value
  end
  attr_accessor :name, :material, :hidden
  attr_reader :definition, :transformation
  def initialize(definition, transformation)
    @definition = definition
    @transformation = transformation
  end
  def bounds_mm
    low = @definition.mesh_min || [0,0,0]
    high = @definition.mesh_max || [@definition.points.map { |p| p[0] }.max, @definition.points.map { |p| p[1] }.max, @definition.extrusion]
    minimum = 3.times.map { |axis| (@transformation.origin[axis] + low[axis]*@transformation.scale[axis])*25.4 }
    maximum = 3.times.map { |axis| (@transformation.origin[axis] + high[axis]*@transformation.scale[axis])*25.4 }
    [minimum,maximum]
  end
end
class MockMaterials
  def initialize
    @by_name = {}
  end
  def [](name)
    @by_name[name]
  end
  def add(name)
    @by_name[name] = Struct.new(:color, :name).new(nil, name)
  end
end
class MockModel
  attr_reader :definitions, :materials
  def initialize
    @definitions = MockDefinitions.new
    @materials = MockMaterials.new
  end
end
require_relative '../kero_cabinet/core'

def near(actual, expected, msg)
  raise "#{msg}: expected #{expected}, actual #{actual}" unless (actual - expected).abs < 0.001
end

def run_case(construction, frame, style, bay_kinds, overrides = {})
  conf = KeroCabinet.clone_defaults
  conf['construction'] = construction
  conf['bottom_construction'] = construction == 'top_bottom_full' ? 'full' : 'between'
  conf['frame'] = frame
  conf['style'] = style
  conf['bays'] = bay_kinds.map { |k|
    { 'kind' => k, 'weight' => 1, 'doors' => 2, 'drawers' => 4, 'shelves' => 2 }
  }
  conf.merge!(overrides)
  config = KeroCabinet.validate_config(conf)
  projection = style == 'overlay' && bay_kinds.any? { |kind| %w[door drawer].include?(kind) } ? config['front'] : 0
  case_depth = config['depth'] - config['back'] - projection
  model = MockModel.new
  Sketchup.active_model = model
  cabinet = MockEntities.new
  KeroCabinet.generate_parts(cabinet, config, model)
  parts = cabinet.instances
  raise 'No panels' if parts.empty?
  names = parts.map(&:name)
  raise 'duplicate component names' if names.uniq.size != names.size
  positions = parts.each_with_object({}) { |part, h| h[part.name] = part.bounds_mm }
  parts.each do |part|
    min, max = part.bounds_mm
    raise "#{part.name} extruded downward" if part.definition.extrusion <= 0
    raise "#{part.name} below floor: #{min[2]}" if min[2] < -0.001
    raise "#{part.name} above height: #{max[2]}" if max[2] > config['height'] + 0.001
    raise "#{part.name} outside width" if min[0] < -0.001 || max[0] > config['width'] + 0.001
    if part.name == 'Back panel'
      raise "Back outside expected depth" unless max[1] <= config['depth'] + 0.001
    else
      raise "#{part.name} beyond back" if max[1] > case_depth + 0.001
    end
  end
  back = positions.fetch('Back panel')
  near(back[0][0], 0.0, 'External back covers entire case width (start)')
  near(back[1][0], config['width'], 'External back covers entire case width (end)')
  near(back[0][1], case_depth, 'External back starts beyond the carcass')
  near(back[1][1], config['depth'] - projection, 'Rear plane accounts for overlay projection')
  near(parts.map { |part| part.bounds_mm[1][1] }.max - parts.map { |part| part.bounds_mm[0][1] }.min, config['depth'], 'Overall depth includes fronts and back')
  near(back[1][1] - back[0][1], config['back'], 'External back thickness')
  near(back[0][2], config['toe'], 'External back starts from case bottom')
  near(back[1][2], config['height'], 'External back extends to case top')
  leftside = positions.fetch('Left side')
  rightside = positions.fetch('Right side')
  near(leftside[1][1], case_depth, 'Left side extends to rear plane')
  near(rightside[1][1], case_depth, 'Right side extends to rear plane')
  top = positions.fetch('Top panel')
  bottom = positions.fetch('Bottom panel')
  near(top[1][2], config['height'], 'Top panel flush with cabinet top')
  near(top[1][1], case_depth, 'Top panel flush with rear edge of sides')
  near(bottom[1][1], case_depth, 'Bottom panel flush with rear edge of sides')
  near(bottom[0][2], config['toe'], 'Bottom panel at toe height')
  if construction == 'sides_full'
    near(leftside[0][2], config['toe'], 'Long sides start at top of toe')
    near(leftside[1][2], config['height'], 'Long sides end at height')
    near(top[0][0], config['panel'], 'Short top starts between sides')
    near(bottom[1][0], config['width'] - config['panel'], 'Short bottom ends between sides')
  else
    near(leftside[0][2], config['toe'] + config['panel'], 'Short sides start above bottom')
    near(leftside[1][2], config['height'] - config['panel'], 'Short sides end below top')
    near(top[0][0], 0, 'Full top starts at x=0')
    near(top[1][0], config['width'], 'Full top spans entire width')
  end
  parts.each do |part|
    next unless part.name.include?('shelf') || part.name.include?('Divider')
    near(part.bounds_mm[1][1], case_depth, "#{part.name} must reach rear plane")
  end
  parts.select { |part| part.name.include?('internal shelf') }.each do |shelf|
    bay_number = shelf.name.split[1]
    doors = parts.select { |part| part.name.start_with?("Bay #{bay_number} door ") }
    doors.each do |door|
      minimum_y = style == 'inset' ? door.bounds_mm[1][1] + config['gap'] : (frame ? config['frame_depth'] : 0)
      expected_y = [frame ? config['frame_depth'] : 0, minimum_y].max
      near(shelf.bounds_mm[0][1], expected_y, 'Shelf clears door back by the configured gap')
    end
  end
  parts.select { |part| part.name.include?('open shelf') }.each do |shelf|
    near(shelf.bounds_mm[0][1], frame ? config['frame_depth'] : 0, 'Open shelves retain full case depth')
  end
  if config['toe'] > 0
    toe_front = positions.fetch('Toe kick front')
    near(toe_front[0][0], 0, 'Toe kick front starts at cabinet left edge')
    near(toe_front[1][0], config['width'], 'Toe kick front covers full cabinet width')
    near(toe_front[0][2], 0, 'Toe kick front reaches floor')
    near(toe_front[1][2], config['toe'], 'Toe kick front reaches case bottom')
  else
    raise 'Unexpected toe kick front at zero height' if positions.key?('Toe kick front')
  end
  timber_parts = parts.select { |part| part.name.start_with?('Toe frame ') }
  if config['toe_frame'] && config['toe'] > 0
    raise 'Missing support frame' if timber_parts.empty?
    front_rail = positions.fetch('Toe frame front rail')
    rear_rail = positions.fetch('Toe frame rear rail')
    near(front_rail[0][1], positions.fetch('Toe kick front')[1][1], 'Timber sits behind toe kick front')
    near(front_rail[1][2], config['toe'], 'Timber supports case bottom')
    near(front_rail[1][2] - front_rail[0][2], config['timber_height'], 'Upright timber height')
    near(front_rail[1][1] - front_rail[0][1], config['timber_thickness'], 'Timber thickness')
    timber_parts.each do |part|
      min, max = part.bounds_mm
      if part.name =~ /(?:left|right|cross) rail/
        near(min[1], front_rail[1][1], 'Butt joint at front rail')
        near(max[1], rear_rail[0][1], 'Butt joint at rear rail')
      elsif part.name.include?('leg')
        near(min[2], 0, 'Leg reaches floor')
        near(max[2], front_rail[0][2], 'Leg supports upper frame')
      end
    end
    timber_parts.combination(2) do |first, second|
      a, b = first.bounds_mm
      c, d = second.bounds_mm
      overlap = 3.times.all? { |axis| [b[axis], d[axis]].min - [a[axis], c[axis]].max > 0.001 }
      raise "Overlapping timber: #{first.name} / #{second.name}" if overlap
    end
  else
    raise 'Unexpected support frame' unless timber_parts.empty?
  end
  drawer_fronts = parts.select { |part| part.name =~ /drawer front/ }
  drawer_boxes = parts.select { |part| part.name =~ /drawer \d+ left side/ }
  raise 'missing drawer boxes' unless drawer_boxes.size == 4 * bay_kinds.count('drawer')
  drawer_fronts.each do |front|
    front_min, front_max = front.bounds_mm
    raise 'Drawer front is inverted' if front_min[2] >= front_max[2]
  end
  puts "OK #{construction} frame=#{frame} style=#{style} bays=#{bay_kinds.join(',')} parts=#{parts.size}"
end

%w[sides_full top_bottom_full].each do |construction|
  [true, false].each do |frame|
    %w[inset overlay].each do |style|
      [['door', 'drawer'], ['door', 'drawer', 'open']].each do |bays|
        run_case(construction, frame, style, bays)
      end
    end
  end
end
%w[sides_full top_bottom_full].each do |construction|
  [true, false].each do |frame|
    run_case(construction, frame, 'inset', ['door', 'open'],
      'front' => 32, 'frame_depth' => 12, 'gap' => 6)
  end
end
run_case('sides_full', false, 'inset', ['door', 'open'], 'toe' => 150)
run_case('top_bottom_full', true, 'overlay', ['door'], 'width' => 3000)
run_case('sides_full', false, 'inset', ['door'], 'toe' => 0)
run_case('sides_full', false, 'inset', ['door'], 'toe' => 50, 'toe_frame' => false)
run_case('sides_full', true, 'inset', ['door'], 'toe' => 60, 'timber_height' => 60, 'timber_thickness' => 30)
bad = KeroCabinet.clone_defaults
bad['toe'] = 80
begin
  KeroCabinet.validate_config(bad)
  raise 'Short toe height should reject upright 100 mm timber'
rescue ArgumentError => error
  raise unless error.message.include?('Toe kick height')
end
run_case('sides_full', false, 'inset', ['door', 'open'], 'back' => 24)
run_case('top_bottom_full', true, 'overlay', ['door'], 'back' => 3)
puts 'All 27 geometry configurations passed, including butt joints, frame clearance, legs, and inset shelves.'  
