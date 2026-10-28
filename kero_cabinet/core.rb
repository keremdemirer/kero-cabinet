# frozen_string_literal: true
# Kero Cabinet v0.5.1, SketchUp 2020+; all design inputs use millimetres.
require 'sketchup.rb'
require 'json'
require_relative 'updater'

module KeroCabinet
  extend self

  DICT = 'kero_cabinet'.freeze
  VERSION = '0.5.1'.freeze

  DEFAULT = {
    'name' => 'Parametric Cabinet',
    'width' => 1200,
    'height' => 850,
    'depth' => 560,
    'panel' => 18,
    'construction' => 'sides_full',
    'top_construction' => 'full',
    'bottom_construction' => 'between',
    'back_construction' => 'full',
    'rail_width' => 100,
    'drawer_thickness' => 12,
    'drawer_bottom' => 12,
    'back' => 6,
    'front' => 18,
    'toe' => 100,
    'toe_frame' => true,
    'timber_height' => 100,
    'timber_thickness' => 50,
    'frame' => true,
    'frame_width' => 38,
    'frame_depth' => 20,
    'style' => 'inset',
    'gap' => 2,
    'bays' => [
      { 'kind' => 'door', 'weight' => 1, 'doors' => 2, 'shelves' => 1, 'drawers' => 4 },
      { 'kind' => 'drawer', 'weight' => 1, 'doors' => 1, 'shelves' => 0, 'drawers' => 4 }
    ]
  }.freeze

  def clone_defaults
    JSON.parse(JSON.generate(DEFAULT))
  end

  def mm(number)
    number.to_f / 25.4
  end

  def show_dialog(instance = nil)
    config = clone_defaults
    if instance && instance.valid?
      raw = instance.get_attribute(DICT, 'config')
      if raw.is_a?(String)
        stored = JSON.parse(raw)
        config = clone_defaults.merge(stored)
        unless stored.key?('bottom_construction')
          config['bottom_construction'] = stored['construction'] == 'top_bottom_full' ? 'full' : 'between'
        end
      end
    end

    dialog = UI::HtmlDialog.new(
      dialog_title: instance ? 'Kero Cabinet | Edit' : 'Kero Cabinet | New',
      preferences_key: 'KeroCabinet.ParametricCabinet',
      scrollable: true,
      resizable: true,
      width: 620,
      height: 790,
      min_width: 500,
      min_height: 540,
      style: UI::HtmlDialog::STYLE_DIALOG
    )

    initial = JSON.generate(config).gsub('</', '<\\/')
    dialog.set_html(dialog_html.sub('/* INITIAL_CONFIG */ null', initial))
    dialog.add_action_callback('submit') do |_context, raw|
      begin
        parsed = JSON.parse(raw)
        validated = validate_config(parsed)
        build_cabinet(validated, instance)
        dialog.close
      rescue StandardError => e
        dialog.execute_script("showError(#{JSON.generate(e.message)})")
        puts "[Kero Cabinet] #{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}" 
      end
    end

    @dialogs ||= []
    @dialogs << dialog
    dialog.set_on_closed { @dialogs.delete(dialog) }
    dialog.show
    dialog.center
  rescue StandardError => e
    UI.messagebox("Could not open Kero Cabinet:\n#{e.message}")
  end

  def number_between!(config, key, low, high)
    n = Float(config[key])
    raise ArgumentError, "#{key}: must be between #{low} and #{high} mm." unless n.finite? && n.between?(low, high)
    config[key] = n
  rescue TypeError, ArgumentError => e
    raise ArgumentError, e.message.include?(key) ? e.message : "#{key}: enter a valid number."
  end

  def integer_between!(hash, key, low, high)
    n = Integer(hash[key])
    raise ArgumentError, "#{key}: must be between #{low} and #{high}." unless n.between?(low, high)
    hash[key] = n
  rescue TypeError, ArgumentError => e
    raise ArgumentError, e.message.include?(key) ? e.message : "#{key}: enter a valid integer."
  end

  def validate_config(source)
    raise ArgumentError, 'Invalid configuration data.' unless source.is_a?(Hash)
    c = clone_defaults.merge(source)
    c['name'] = c['name'].to_s.strip[0, 80]
    c['name'] = 'Parametric Cabinet' if c['name'].empty?
    {
      'width' => [300, 5000], 'height' => [350, 3500], 'depth' => [250, 1200],
      'rail_width' => [40, 200], 'drawer_thickness' => [6, 30],
      'drawer_bottom' => [3, 24], 'panel' => [9, 36], 'back' => [3, 24], 'front' => [9, 32],
      'toe' => [0, 250], 'timber_height' => [20, 200],
      'timber_thickness' => [10, 100], 'frame_width' => [25, 90],
      'frame_depth' => [12, 36], 'gap' => [1, 6]
    }.each { |key, (low, high)| number_between!(c, key, low, high) }
    c['construction'] = c['construction'].to_s
    unless %w[sides_full top_bottom_full].include?(c['construction'])
      raise ArgumentError, 'Construction must use full-height sides or full-width top and bottom panels.'
    end
    %w[top_construction back_construction].each do |key|
      raise ArgumentError, "#{key}: choose full or rails." unless %w[full rails].include?(c[key])
    end
    if c['top_construction'] == 'rails' || c['back_construction'] == 'rails'
      c['construction'] = 'sides_full'
    end
    unless source.key?('bottom_construction')
      c['bottom_construction'] = source['construction'] == 'top_bottom_full' ? 'full' : 'between'
    end
    unless %w[between full].include?(c['bottom_construction'])
      raise ArgumentError, 'Bottom construction must be between or full.'
    end
    c['toe_frame'] = (c['toe_frame'] == true)
    if c['toe_frame'] && c['toe'] > 0 && c['toe'] < c['timber_height']
      raise ArgumentError, 'Toe kick height must be at least the upright timber height, or disable the support frame.'
    end
    c['frame'] = (c['frame'] == true)
    c['style'] = c['style'].to_s
    raise ArgumentError, 'Door style must be inset or overlay.' unless %w[inset overlay].include?(c['style'])
    if c['toe'] + 2 * [c['panel'], (c['frame'] ? c['frame_width'] : 0)].max >= c['height']
      raise ArgumentError, 'Height is insufficient for the toe kick and top/bottom sections.'
    end
    frame_depth = c['frame'] ? c['frame_depth'] : 0.0
    if c['depth'] - (c['back_construction'] == 'full' ? c['back'] : 0) - frame_depth < 190
      raise ArgumentError, 'Case depth is too small.'
    end
    case_rear = c['depth'] - (c['back_construction'] == 'full' ? c['back'] : 0)
    rear_limit = case_rear - (c['back_construction'] == 'rails' ? c['panel'] : 0)
    if c['top_construction'] == 'rails' && rear_limit - frame_depth <= 2 * c['rail_width']
      raise ArgumentError, 'Top support rails need more depth or a smaller rail width.'
    end
    if c['back_construction'] == 'rails' && c['height'] - c['toe'] - 2 * c['panel'] <= 2 * c['rail_width']
      raise ArgumentError, 'Back support rails need more height or a smaller rail width.'
    end
    unless c['bays'].is_a?(Array) && c['bays'].length.between?(1, 6)
      raise ArgumentError, 'Between 1 and 6 vertical bays are required.'
    end
    c['bays'].each do |bay|
      raise ArgumentError, 'Invalid bay data.' unless bay.is_a?(Hash)
      bay['kind'] = bay['kind'].to_s
      raise ArgumentError, 'Invalid bay type.' unless %w[door drawer open].include?(bay['kind'])
      bay['weight'] = Float(bay['weight'])
      raise ArgumentError, 'Bay weight must be between 0.2 and 10.' unless bay['weight'].finite? && bay['weight'].between?(0.2, 10.0)
      integer_between!(bay, 'doors', 1, 2)
      integer_between!(bay, 'drawers', 1, 8)
      integer_between!(bay, 'shelves', 0, 8)
    end
    total = c['bays'].sum { |b| b['weight'] }
    widths = c['bays'].map { |b| c['width'] * b['weight'] / total }
    minimum = c['panel'] * 2 + (c['frame'] ? c['frame_width'] : 0) + 110
    raise ArgumentError, "Each bay must be at least #{minimum.round} mm wide. Increase the width or adjust the weights." if widths.any? { |w| w < minimum }
    c
  end

  def materials(model)
    colors = {
      'Case' => [214, 179, 130],
      'Back panel' => [198, 168, 130],
      'Face frame' => [141, 99, 66],
      'Door / drawer front' => [183, 137, 93],
      'Drawer box' => [227, 204, 161],
      'Toe kick timber' => [196, 159, 106]
    }
    colors.each_with_object({}) do |(name, rgb), h|
      material_name = "KC | #{name}"
      material = model.materials[material_name] || model.materials.add(material_name)
      material.color = Sketchup::Color.new(*rgb)
      h[name] = material
    end
  end

  # Each individual wooden part is a solid SketchUp ComponentInstance.
  # OpenCutList reads components, not groups. Coordinates and dimensions use mm.
  # x = width, y = depth (front is y = 0), z = height.
  def box(entities, name, material_name, x, y, z, sx, sy, sz, palette)
    dims = [sx, sy, sz]
    return if dims.any? { |v| v <= 0.25 }

    model = Sketchup.active_model
    definition = model.definitions.add("KC | #{name}")
    dx, dy, dz = dims.map { |v| mm(v) }
    points = [
      [0, 0, 0], [dx, 0, 0],
      [dx, dy, 0], [0, dy, 0]
    ]
    face = definition.entities.add_face(points)
    raise "Could not create face: #{name}" unless face
    # SketchUp forcibly orients faces drawn on the component's Z=0 ground plane
    # downwards, regardless of vertex winding. pushpull follows the face normal.
    # Always reverse a downward-facing face before extruding a positive height.
    face.reverse! unless face.normal.samedirection?(Z_AXIS)
    face.pushpull(dz)
    definition.description = name

    origin = [x, y, z].map { |v| mm(v) }
    instance = entities.add_instance(definition, Geom::Transformation.new(origin))
    instance.name = name
    instance.material = palette[material_name]
    instance
  end

  def generate_parts(entities, c, model)
    w, h, d = c.values_at('width', 'height', 'depth')
    d -= c['back'] if c['back_construction'] == 'full'
    t, bt, ft, toe = c.values_at('panel', 'back', 'front', 'toe')
    face_frame = c['frame']
    fw = face_frame ? c['frame_width'] : 0.0
    fd = face_frame ? c['frame_depth'] : 0.0
    g = c['gap']
    palette = materials(model)
    add = lambda do |name, material, x, y, z, sx, sy, sz|
      box(entities, name, material, x, y, z, sx, sy, sz, palette)
    end

    # Carcass construction. The selected full-length direction also determines
    # the physical size of the panels, not merely a visual highlight.
    # The back thickness is reserved within the requested overall depth.
    # The back is applied OUTSIDE the carcass, not captured between its parts.
    # This also keeps top and bottom flush with the rear edge of the side panels.
    rear_inside = d - (c['back_construction'] == 'rails' ? t : 0)
    depth_inside = rear_inside - fd
    full_bottom = c['bottom_construction'] == 'full'
    full_top = c['construction'] == 'top_bottom_full' && c['top_construction'] == 'full'
    side_bottom = toe + (full_bottom ? t : 0)
    side_top = h - (full_top ? t : 0)
    add.call('Left side', 'Case', 0, fd, side_bottom, t, d - fd, side_top - side_bottom)
    add.call('Right side', 'Case', w - t, fd, side_bottom, t, d - fd, side_top - side_bottom)
    add.call('Bottom panel', 'Case', full_bottom ? 0 : t, fd, toe,
      full_bottom ? w : w - 2*t, d - fd, t)
    if c['top_construction'] == 'full'
      add.call('Top panel', 'Case', full_top ? 0 : t, fd, h - t,
        full_top ? w : w - 2*t, d - fd, t)
    end
    rail = c['rail_width']
    if c['top_construction'] == 'rails'
      add.call('Top front support rail', 'Case', t, fd, h - t, w - 2*t, rail, t)
      add.call('Top rear support rail', 'Case', t, rear_inside - rail, h - t, w - 2*t, rail, t)
    end
    if c['back_construction'] == 'full'
      add.call('Back panel', 'Back panel', 0, d, toe, w, bt, h - toe)
    else
      upper = c['top_construction'] == 'full' ? h - t : h
      add.call('Back upper support rail', 'Case', t, d - t, upper - rail, w - 2*t, t, rail)
      add.call('Back lower support rail', 'Case', t, d - t, toe + t, w - 2*t, t, rail)
    end
    if toe > 0
      recess = [65.0, (d-fd)/3.0].min
      add.call('Toe kick front', 'Case', 0, fd + recess, 0, w, t, toe)
    end

    bay_total = c['bays'].sum { |b| b['weight'] }
    bounds = [0.0]
    c['bays'].each { |bay| bounds << bounds.last + w * bay['weight'] / bay_total }
    bounds[-1] = w
    n = c['bays'].length

    generate_toe_frame(add, c, bounds, fd) if c['toe_frame'] && toe > 0

    # Full-height intermediate panels and face-frame stiles align with bays.
    (1...n).each do |i|
      x = bounds[i]
      add.call("Divider #{i}", 'Case', x - t/2, fd, toe + t, t, depth_inside, h - toe - 2*t)
    end

    if face_frame
      add.call('Left face frame stile', 'Face frame', 0, 0, toe, fw, fd, h - toe)
      add.call('Right face frame stile', 'Face frame', w-fw, 0, toe, fw, fd, h-toe)
      add.call('Bottom face frame rail', 'Face frame', fw, 0, toe, w-2*fw, fd, fw)
      add.call('Top face frame rail', 'Face frame', fw, 0, h-fw, w-2*fw, fd, fw)
      (1...n).each do |i|
        add.call("Middle face frame stile #{i}", 'Face frame', bounds[i]-fw/2, 0,
                 toe+fw, fw, fd, h-toe-2*fw)
      end
    end

    door_bottom = toe + (face_frame ? fw : t)
    door_top = h - (face_frame ? fw : t)
    cavity_bottom = toe + t
    cavity_top = h - t

    c['bays'].each_with_index do |bay, i|
      start_x = bounds[i]
      end_x = bounds[i+1]
      opening_left = i.zero? ? (face_frame ? fw : t) : start_x + (face_frame ? fw/2 : t/2)
      opening_right = i == n-1 ? (w - (face_frame ? fw : t)) : end_x - (face_frame ? fw/2 : t/2)
      cavity_left = i.zero? ? t : start_x + t/2
      cavity_right = i == n-1 ? w-t : end_x-t/2
      cavity_width = cavity_right - cavity_left

      # Inset fronts fit within openings. Overlay fronts cover part of the frame.
      if c['style'] == 'inset'
        front_left = opening_left + g
        front_right = opening_right - g
        front_bottom = door_bottom + g
        front_top = door_top - g
        front_y = face_frame ? g : fd
      else
        front_left = start_x + (i.zero? ? g : g/2)
        front_right = end_x - (i == n-1 ? g : g/2)
        front_bottom = toe + g
        front_top = h - g
        front_y = -ft
      end
      front_width = front_right - front_left
      front_height = front_top - front_bottom
      raise ArgumentError, "Bay #{i+1}: available opening is too small." if front_width < 60 || front_height < 100

      case bay['kind']
      when 'door'
        # Inset doors occupy case depth. Keep shelves behind the door back,
        # with the configured gap, while preserving their rear alignment.
        shelf_y = c['style'] == 'inset' ? [fd, front_y + ft + g].max : fd
        shelf_depth = rear_inside - shelf_y
        count = bay['doors']
        item_width = (front_width - (count - 1)*g) / count
        count.times do |j|
          x = front_left + j*(item_width + g)
          add.call("Bay #{i+1} door #{j+1}", 'Door / drawer front',
                   x, front_y, front_bottom, item_width, ft, front_height)
        end
        bay['shelves'].times do |j|
          z = cavity_bottom + (j+1)*(cavity_top - cavity_bottom)/(bay['shelves']+1.0) - t/2
          add.call("Bay #{i+1} internal shelf #{j+1}", 'Case',
                   cavity_left, shelf_y, z, cavity_width, shelf_depth, t)
        end
      when 'drawer'
        count = bay['drawers']
        cell = (front_height - (count-1)*g)/count
        raise ArgumentError, "Bay #{i+1}: drawer height is too small." if cell < 85
        count.times do |j|
          z_front = front_bottom + j*(cell+g)
          add.call("Bay #{i+1} drawer front #{j+1}", 'Door / drawer front',
                   front_left, front_y, z_front, front_width, ft, cell)
          # Preserve outer box dimensions and runner clearances as stock changes.
          side_clearance = 12.5
          dbx = cavity_left + side_clearance
          dbw = cavity_width - 2*side_clearance
          dby = fd + 18
          dbd = rear_inside - 25 - dby
          dbh = [125.0, cell - 25.0].min
          wanted_z = z_front + [12.0, (cell-dbh)/2].max
          # Respect carcass bottom and top even when an overlay front covers the rails.
          dbz = [[wanted_z, cavity_bottom + 4].max, cavity_top - dbh - 4].min
          dt = c['drawer_thickness']
          bottom_t = c['drawer_bottom']
          raise ArgumentError, 'Insufficient internal space for the drawer box.' if dbw < 80 || dbd < 100 || dbh < 60
          if dbw - 2*dt <= 0.25 || dbd - 2*dt <= 0.25 || dbh - bottom_t <= 0.25
            raise ArgumentError, 'Drawer stock is too thick for the available box dimensions.'
          end
          tag = "Bay #{i+1} drawer #{j+1}"
          add.call("#{tag} left side", 'Drawer box', dbx, dby, dbz, dt, dbd, dbh)
          add.call("#{tag} right side", 'Drawer box', dbx+dbw-dt, dby, dbz, dt, dbd, dbh)
          add.call("#{tag} front rail", 'Drawer box', dbx+dt, dby, dbz, dbw-2*dt, dt, dbh)
          add.call("#{tag} back rail", 'Drawer box', dbx+dt, dby+dbd-dt, dbz, dbw-2*dt, dt, dbh)
          add.call("#{tag} bottom", 'Drawer box', dbx+dt, dby+dt, dbz,
                   dbw-2*dt, dbd-2*dt, bottom_t)
        end
      when 'open'
        bay['shelves'].times do |j|
          z = cavity_bottom + (j+1)*(cavity_top - cavity_bottom)/(bay['shelves']+1.0) - t/2
          add.call("Bay #{i+1} open shelf #{j+1}", 'Case',
                   cavity_left, fd, z, cavity_width, depth_inside, t)
        end
      end
    end
  end

  # Full-width front/rear rails; transverse members butt between them.
  # At the default 100 mm toe height the upright 100 mm timbers sit on the floor.
  def generate_toe_frame(add, c, bounds, front_offset)
    w, d, toe = c.values_at('width', 'depth', 'toe')
    d -= c['back'] if c['back_construction'] == 'full'
    height, thickness = c.values_at('timber_height', 'timber_thickness')
    recess = [65.0, (d - front_offset) / 3.0].min
    front_y = front_offset + recess + c['panel']
    rear_y = d - thickness
    inside_depth = rear_y - front_y - thickness
    if inside_depth <= 0.25 || w <= 2 * thickness + 0.25
      raise ArgumentError, 'The toe kick support frame does not fit. Reduce timber thickness or increase case dimensions.'
    end
    z = toe - height
    add.call('Toe frame front rail', 'Toe kick timber', 0, front_y, z, w, thickness, height)
    add.call('Toe frame rear rail', 'Toe kick timber', 0, rear_y, z, w, thickness, height)
    add.call('Toe frame left rail', 'Toe kick timber', 0, front_y + thickness, z, thickness, inside_depth, height)
    add.call('Toe frame right rail', 'Toe kick timber', w - thickness, front_y + thickness, z, thickness, inside_depth, height)

    # Support each bay boundary, adding intermediate supports for spans over 600 mm.
    centers = bounds[1...-1].dup
    bounds.each_cons(2) do |left, right|
      divisions = ((right - left) / 600.0).ceil
      (1...divisions).each { |i| centers << left + (right - left) * i / divisions }
    end
    centers.sort.each_with_index do |x, i|
      if x - thickness / 2 < thickness || x + thickness / 2 > w - thickness
        raise ArgumentError, 'A toe frame cross rail is too close to an end rail. Reduce timber thickness.'
      end
      add.call("Toe frame cross rail #{i + 1}", 'Toe kick timber',
        x - thickness / 2, front_y + thickness, z, thickness, inside_depth, height)
    end

    # Taller toe spaces need legs below the top frame to reach the floor.
    return unless z > 0.25
    leg_width = height
    supports = [leg_width / 2.0] + centers.sort + [w - leg_width / 2.0]
    if supports.each_cons(2).any? { |left, right| right - left < leg_width }
      raise ArgumentError, 'Toe frame legs would overlap. Reduce upright timber height or increase bay widths.'
    end
    supports.each_with_index do |x, i|
      [front_y, rear_y].each_with_index do |y, j|
        add.call("Toe frame leg #{i + 1} #{j == 0 ? 'front' : 'rear'}", 'Toe kick timber',
          x - leg_width / 2, y, 0, leg_width, thickness, z)
      end
    end
  end

  def build_cabinet(c, instance)
    model = Sketchup.active_model
    model.start_operation(instance ? 'Edit Kero Cabinet' : 'Create Kero Cabinet', true)
    begin
      if instance && instance.valid?
        raise 'The selected object is no longer available.' unless instance.is_a?(Sketchup::ComponentInstance)
        instance.make_unique
        definition = instance.definition
        definition.entities.clear!
      else
        definition = model.definitions.add(c['name'])
        instance = model.active_entities.add_instance(definition, Geom::Transformation.new)
      end
      generate_parts(definition.entities, c, model)
      definition.name = c['name']
      definition.description = "Kero Cabinet #{VERSION}, created from parameters in millimetres"
      instance.name = c['name']
      instance.set_attribute(DICT, 'config', JSON.generate(c))
      instance.set_attribute(DICT, 'version', VERSION)
      model.selection.clear
      model.selection.add(instance)
      model.commit_operation
    rescue StandardError
      model.abort_operation
      raise
    end
    instance
  end

  def selected_cabinet
    selection = Sketchup.active_model.selection
    return nil unless selection.length == 1
    item = selection.first
    return nil unless item.is_a?(Sketchup::ComponentInstance)
    return nil unless item.get_attribute(DICT, 'config').is_a?(String)
    item
  end

  def edit_selected
    cabinet = selected_cabinet
    return UI.messagebox('Select a Kero Cabinet component first.') unless cabinet
    show_dialog(cabinet)
  end

  def dialog_html
    <<~'HTML'
      <!doctype html>
      <html lang="en">
      <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        * {box-sizing:border-box} body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;margin:0;background:#f5f4f1;color:#272727;font-size:13px}
        header{padding:20px 22px 15px;background:#242526;color:#fff} h1{font-size:20px;margin:0 0 4px}header p{margin:0;color:#c5c5c5}
        main{padding:18px 20px 85px}.section{background:white;border:1px solid #e3e1dc;border-radius:10px;padding:16px;margin-bottom:13px}
        h2{font-size:14px;margin:0 0 12px} .grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}
        .grid.two{grid-template-columns:repeat(2,minmax(0,1fr))}label{display:block;font-size:11px;font-weight:600;color:#565656;margin-bottom:4px}
        input,select{width:100%;height:34px;border:1px solid #d4d1cc;background:white;border-radius:6px;padding:6px;font-size:13px;color:#222}
        input[type=checkbox]{width:17px;height:17px;accent-color:#84613e} .check{display:flex;align-items:center;gap:8px;margin:12px 0 0}
        .check label{margin:0}.hint{font-size:11px;color:#707070;line-height:1.45;margin:9px 0 0}
        .construction-options{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
        .construction-option{display:block;position:relative;cursor:pointer;margin:0}
        .construction-option input{position:absolute;opacity:0;width:1px;height:1px}
        .construction-card{height:100%;border:2px solid #dedbd4;border-radius:10px;background:#faf9f7;padding:12px;text-align:center;display:flex;align-items:center;flex-direction:column;gap:5px}
        .construction-card svg{display:block;width:100%;max-width:168px;height:126px}
        .construction-option input:checked+.construction-card{border-color:#3c7354;background:#eef6f0}
        .construction-option input:focus-visible+.construction-card{outline:3px solid #78a28a;outline-offset:2px}
        .construction-card strong{font-size:13px;color:#262626}
        .construction-card small{color:#666;font-size:11px;line-height:1.3}
        .bay{background:#faf9f7;border:1px solid #e7e4df;border-radius:8px;padding:12px;margin:8px 0}
        .bayhead{display:flex;justify-content:space-between;align-items:center;margin:0 0 10px;font-weight:700}
        .ghost{background:#fff;color:#555;border:1px solid #d2cec9;border-radius:6px;padding:8px 10px;cursor:pointer}
        .remove{font-size:12px;padding:4px 9px}.actions{position:fixed;bottom:0;left:0;right:0;padding:12px 20px;background:#fff;border-top:1px solid #ddd;display:flex;align-items:center;gap:12px}
        .primary{background:#3c7354;color:#fff;border:0;border-radius:7px;padding:12px 18px;font-weight:700;cursor:pointer}
        .error{color:#ae3429;flex:1;font-size:12px;overflow-wrap:anywhere}.spacer{flex:1}
        @media(max-width:560px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
      </style>
      </head>
      <body>
      <header><h1>Kero Cabinet</h1><p>Parametric SketchUp cabinet builder - v0.5.1</p></header>
      <main>
        <section class="section">
          <h2>Case dimensions</h2>
          <div class="grid">
            <div><label for="name">Component name</label><input id="name" type="text" style="min-width:0"></div>
            <div><label for="width">Width (mm)</label><input id="width" type="number" step="1"></div>
            <div><label for="height">Height (mm)</label><input id="height" type="number" step="1"></div>
            <div><label for="depth">Depth incl. back (mm)</label><input id="depth" type="number" step="1"></div>
            <div><label for="panel">Case panel (mm)</label><input id="panel" type="number" step="1"></div>
            <div><label for="back">Back panel (mm)</label><input id="back" type="number" step="1"></div>
            <div><label for="front">Door/front thickness (mm)</label><input id="front" type="number" step="1"></div>
            <div><label for="gap">Front gap (mm)</label><input id="gap" type="number" step="0.5"></div>
          </div>
          <p class="hint">Depth includes the external back panel. The case is shortened by the back thickness; overlay fronts project forward separately. Enter the total height including the toe kick.</p>
        </section>
        <section class="section">
          <h2>Toe kick</h2>
          <div class="grid two">
            <div><label for="toe">Toe kick height (mm)</label><input id="toe" type="number" step="1"></div>
          </div>
          <div class="check"><input id="toe_frame" type="checkbox"><label for="toe_frame">Create timber support frame</label></div>
          <div class="grid two" style="margin-top:10px">
            <div><label for="timber_height">Upright timber height (mm)</label><input id="timber_height" type="number" min="20" max="200"></div>
            <div><label for="timber_thickness">Timber thickness (mm)</label><input id="timber_thickness" type="number" min="10" max="100"></div>
          </div>
          <p class="hint">Default: 50 x 100 mm timber with 100 mm upright. Butt joints, full-width front/rear rails and cross rails at bay boundaries, with extra rails for spans over 600 mm. The front panel spans the full cabinet width. The frame sits behind the toe kick front; taller toe spaces receive legs. No frame is created at zero toe height.</p>
        </section>
        <section class="section">
          <h2>Top / Bottom / Back construction</h2>
          <div class="grid">
            <div><label for="top_construction">Top construction</label><select id="top_construction" onchange="updateConstruction()"><option value="full">Full panel</option><option value="rails">Support rails</option></select></div>
            <div><label for="bottom_construction">Bottom construction</label><select id="bottom_construction"><option value="between">Between sides</option><option value="full">Full width</option></select></div>
            <div><label for="back_construction">Back construction</label><select id="back_construction" onchange="updateConstruction()"><option value="full">Full panel</option><option value="rails">Support rails</option></select></div>
            <div><label for="rail_width">Rail width (mm)</label><input id="rail_width" type="number" min="40" max="200"></div>
          </div>
          <p class="hint">Support rails use the case material and thickness. Rails extend the sides to the cabinet top. A full-width bottom sits under the sides. With back rails, no external back thickness is deducted from the overall depth.</p>
          <h3>Top panel arrangement</h3>
          <div class="construction-options" role="radiogroup" aria-label="Case construction">
            <label class="construction-option">
              <input type="radio" name="construction" value="sides_full">
              <span class="construction-card">
                <svg viewBox="0 0 190 140" role="img" aria-label="Full-height side panels; shorter top and bottom panels">
                  <rect x="18" y="11" width="154" height="118" rx="2" fill="#faf6eb" stroke="#9c917d" stroke-width="2"/>
                  <rect x="18" y="11" width="20" height="118" fill="#4f8f70" stroke="#326b51" stroke-width="1.5"/>
                  <rect x="152" y="11" width="20" height="118" fill="#4f8f70" stroke="#326b51" stroke-width="1.5"/>
                  <rect x="38" y="11" width="114" height="20" fill="#d9b985" stroke="#92794e" stroke-width="1.5"/>
                  <rect x="38" y="109" width="114" height="20" fill="#d9b985" stroke="#92794e" stroke-width="1.5"/>
                </svg>
                <strong>Top between sides</strong>
                <small>Top fits between the sides; bottom is selected separately</small>
              </span>
            </label>
            <label class="construction-option">
              <input type="radio" name="construction" value="top_bottom_full">
              <span class="construction-card">
                <svg viewBox="0 0 190 140" role="img" aria-label="Full-width top and bottom panels; shorter side panels">
                  <rect x="18" y="11" width="154" height="118" rx="2" fill="#faf6eb" stroke="#9c917d" stroke-width="2"/>
                  <rect x="18" y="11" width="154" height="20" fill="#4f8f70" stroke="#326b51" stroke-width="1.5"/>
                  <rect x="18" y="109" width="154" height="20" fill="#4f8f70" stroke="#326b51" stroke-width="1.5"/>
                  <rect x="18" y="31" width="20" height="78" fill="#d9b985" stroke="#92794e" stroke-width="1.5"/>
                  <rect x="152" y="31" width="20" height="78" fill="#d9b985" stroke="#92794e" stroke-width="1.5"/>
                </svg>
                <strong>Full-width top</strong>
                <small>Sides fit under the top; bottom is selected separately</small>
              </span>
            </label>
          </div>
          <p class="hint">Top arrangement is locked when support rails are selected. Bottom construction stays independent. A full-width bottom raises the side start by its thickness without changing overall height.</p>
        </section>
        <section class="section">
          <h2>Face frame and door style</h2>
          <div class="grid two">
            <div><label for="style">Door placement</label><select id="style"><option value="inset">Inset</option><option value="overlay">Overlay</option></select></div>
            <div><label for="frame_width">Face frame width (mm)</label><input id="frame_width" type="number" step="1"></div>
            <div><label for="frame_depth">Face frame thickness (mm)</label><input id="frame_depth" type="number" step="1"></div>
          </div>
          <div class="check"><input id="frame" type="checkbox" onchange="updateFrame()"><label for="frame">Create face frame</label></div>
        </section>
        <section class="section">
          <h2>Drawer construction</h2>
          <div class="grid two">
            <div><label for="drawer_thickness">Drawer box thickness (mm)</label><input id="drawer_thickness" type="number" min="6" max="30"></div>
            <div><label for="drawer_bottom">Drawer bottom thickness (mm)</label><input id="drawer_bottom" type="number" min="3" max="24"></div>
          </div>
          <p class="hint">Box sides and front/back members share the box thickness. The bottom fits between them. Visible drawer fronts use Door/front thickness. Outer box size and runner clearances stay unchanged.</p>
        </section>
        <section class="section">
          <h2>Vertical bays</h2>
          <p class="hint" style="margin:0 0 10px">Each bay can contain doors, drawers, or open shelves. Weights determine the relative bay widths.</p>
          <div id="bays"></div>
          <button class="ghost" onclick="addBay()" type="button">+ Add bay</button>
        </section>
      </main>
      <div class="actions"><span class="error" id="error"></span><span class="spacer"></span><button class="primary" type="button" onclick="submitConfig()">Create / update component</button></div>
      <script>
        const initial = /* INITIAL_CONFIG */ null;
        let bays = JSON.parse(JSON.stringify(initial.bays));
        const ids = ['name','width','height','depth','panel','back','front','toe','gap','style','frame_width','frame_depth','timber_height','timber_thickness','top_construction','bottom_construction','back_construction','rail_width','drawer_thickness','drawer_bottom'];
        for (const id of ids) document.getElementById(id).value = initial[id];
        document.getElementById('frame').checked = !!initial.frame;
        document.getElementById('toe_frame').checked = !!initial.toe_frame;
        (document.querySelector('input[name=construction][value="'+(initial.construction||'sides_full')+'"]') || document.querySelector('input[name=construction][value=sides_full]')).checked = true;
        const n = (v) => Number(v);
        const escapeHtml = (s) => String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/"/g,'&quot;');
        function updateConstruction(){
          const rails=['top_construction','back_construction'].some(id=>document.getElementById(id).value==='rails');
          if(rails) document.querySelector('input[name=construction][value=sides_full]').checked=true;
          for(const radio of document.querySelectorAll('input[name=construction]')) radio.disabled=rails;
          document.getElementById('rail_width').disabled=!rails;
          document.getElementById('back').disabled=document.getElementById('back_construction').value==='rails';
        }
        function updateFrame(){
          for(const id of ['frame_width','frame_depth']) document.getElementById(id).disabled = !document.getElementById('frame').checked;
        }
        function addBay(){
          if(bays.length>=6) return showError('You can add up to 6 bays.');
          bays.push({kind:'door',weight:1,doors:1,drawers:4,shelves:1}); renderBays();
        }
        function removeBay(i){ if(bays.length>1){bays.splice(i,1);renderBays();} }
        function changeBay(i,key,value){bays[i][key]=key==='kind'?value:Number(value); if(key==='kind')renderBays();}
        function renderBays(){
          document.getElementById('bays').innerHTML = bays.map((b,i)=>{
            const third = b.kind==='drawer' ? `<div><label>Drawer count</label><input type="number" min="1" max="8" value="${b.drawers}" onchange="changeBay(${i},'drawers',this.value)"></div>`
             : b.kind==='door' ? `<div><label>Door count (side by side)</label><select onchange="changeBay(${i},'doors',this.value)"><option value="1" ${b.doors==1?'selected':''}>1</option><option value="2" ${b.doors==2?'selected':''}>2</option></select></div>` : '';
            const shelves = b.kind!=='drawer' ? `<div><label>${b.kind==='door'?'Internal shelf':'Shelf'} count</label><input type="number" min="0" max="8" value="${b.shelves}" onchange="changeBay(${i},'shelves',this.value)"></div>` : '';
            return `<div class="bay"><div class="bayhead"><span>Bay ${i+1}</span><button class="ghost remove" onclick="removeBay(${i})" type="button">Remove</button></div>
              <div class="grid"><div><label>Type</label><select onchange="changeBay(${i},'kind',this.value)">
                <option value="door" ${b.kind==='door'?'selected':''}>Doors</option><option value="drawer" ${b.kind==='drawer'?'selected':''}>Drawers</option><option value="open" ${b.kind==='open'?'selected':''}>Open shelves</option></select></div>
                <div><label>Width weight</label><input type="number" min="0.2" max="10" step="0.1" value="${escapeHtml(b.weight)}" onchange="changeBay(${i},'weight',this.value)"></div>${third}${shelves}</div></div>`;
          }).join('');
        }
        function showError(message){ document.getElementById('error').textContent=message; }
        function submitConfig(){
          showError('');
          const c={}; for(const id of ids) c[id]=['name','style','top_construction','bottom_construction','back_construction'].includes(id)?document.getElementById(id).value:n(document.getElementById(id).value);
          c.toe_frame=document.getElementById('toe_frame').checked;
          c.frame=document.getElementById('frame').checked;
          c.construction=document.querySelector('input[name=construction]:checked').value;
          c.bays=bays.map(b=>({...b}));
          if(!window.sketchup || !window.sketchup.submit) return showError('This panel must be used inside SketchUp.');
          window.sketchup.submit(JSON.stringify(c));
        }
        updateFrame();updateConstruction();renderBays();
      </script>
      </body>
      </html>
    HTML
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins').add_submenu('Kero Cabinet')
    menu.add_item('Create new cabinet...') { show_dialog }
    menu.add_item('Edit selected cabinet...') { edit_selected }
    menu.add_separator
    menu.add_item('Check for updates...') { Updater.check }
    menu.add_item('Update settings...') { Updater.show_settings }
    Updater.startup_check
    UI.add_context_menu_handler do |menu_context|
      item = selected_cabinet
      if item
        menu_context.add_separator
        menu_context.add_item('Kero Cabinet | Edit parameters') { show_dialog(item) }
      end
    end
    file_loaded(__FILE__)
  end
end
