require 'treetop'
Treetop.load 'PATH_TO/grammar/forge_grammar.tt'

parser = ForgeGrammarParser.new
EMPTY_ANVIL = { :name => :silence, :mods => [] , :release => 1 }
map = { "k" => :drum_heavy_kick,
        "s" => :drum_snare_hard,
        "co" => :drum_cymbal_open,
        "cc" => :drum_cymbal_closed,
        "et" => :elec_tick,
        "a1" => :forge_a1,
        "ab1" => :forge_ab1,
        "b1" => :forge_b1,
        "bb1" => :forge_bb1,
        "c2" => :forge_c2,
        "cs2" => :forge_cs2,
        "d2" => :forge_d2,
        "e1" => :forge_e1,
        "e2" => :forge_e2,
        "eb2" => :forge_eb2,
        "f1" => :forge_f1,
        "fs1" => :forge_fs1,
        "g1" => :forge_g1}

define :play_anvil_list do |list,steps,index|
  with_bpm_mul(steps) do
    steps.times do
      play_data_structure list[:content][index]
      index = index + 1
    end
  end
end

define :play_data_structure do |anvil|
  case anvil[:name]
  when :sym
    sample anvil[:content], sustain: 0, release: bt(anvil[:release])
    sleep 1
  when :note
    play anvil[:content], release: anvil[:release]
    sleep 1
  when :sequential
    play_anvil_list anvil, anvil[:content].length, 0
  when :parallel
    density 1/anvil[:release] do
      anvil[:content].each do |list|
        in_thread do
          play_data_structure list
        end
      end
    end
    sleep 1
  when :timed_parallel
    index = anvil[:index]
    steps = anvil[:content][0][:content].length
    density 1.0/anvil[:release] do
      anvil[:content].each do |list|
        in_thread do
          play_anvil_list list, steps, index
        end
      end
    end
    anvil[:index] = anvil[:index] + steps
    sleep 1
  when :word
    if map.has_key?(anvil[:content])
      sample map[anvil[:content]], sustain: 0, release: bt(anvil[:release])
    else
      eval anvil[:content]
    end
    sleep 1
  when :silence
    sleep 1
  end
end

define :ring_to_array do |ring|
  a = []
  ring.each do |e|
    a << e
  end
  a
end

define :apply_mods do |anvil,curley_bracket_parent|
  case anvil[:name]
  when :sequential
    anvil[:content].each do |element|
      apply_mods element,curley_bracket_parent
    end
    anvil[:content].each_index do |list_index|
      element = anvil[:content][list_index]
      element[:mods].each_index do |mod_index|
        mod = element[:mods][mod_index]
        case mod[:name]
        when :mult
          repeats = mod[:content]
          a = ring_to_array anvil[:content]
          element[:mods].delete_at mod_index
          a.delete_at list_index
          repeats.times do
            el = element.dup
            el[:mods] = element[:mods].dup
            a.insert list_index, el
          end
          anvil[:content] = a.ring
          apply_mods anvil, curley_bracket_parent
        when :spread
          sprd = spread(mod[:content][:ammount],mod[:content][:per])
          a = ring_to_array anvil[:content]
          element[:mods].delete_at mod_index
          a.delete_at list_index
          sprd.each do |sprd_el|
            if sprd_el
              el = element.dup
              el[:mods] = element[:mods].dup
              a.insert list_index, el
            else
              el = { :name => :silence }
              el[:mods] = element[:mods].dup
              a.insert list_index, el
            end
          end
          anvil[:content] = a.ring
          apply_mods anvil, curley_bracket_parent
        when :div
          anvil[:content] = apply_divs anvil[:content], curley_bracket_parent
        end
      end
    end
  when :parallel
    anvil[:content].map do |list|
      apply_mods list, false
    end
  when :timed_parallel
    anvil[:content].each_index do |i|
      apply_mods anvil[:content][i], 0 < i
    end
  end
end

# takes a ring, applys the div mod, return the new ring
define :apply_divs do |list,curley_bracket_parent|
  silent_arr = []
  a = ring_to_array list
  added_els = 0
  list.each_index do |list_i|
    silent_arr << EMPTY_ANVIL
    el = list[list_i]
    el[:mods].each_index do |mod_i|
      mod = el[:mods][mod_i]
      case mod[:name]
      when :div
        div = mod[:content]
        el[:mods].delete_at mod_i
        el[:release] = el[:release]*div
        (div-1).times do
          added_els = added_els + 1
          a.insert list_i + added_els, EMPTY_ANVIL
        end
      end
    end
  end
  if curley_bracket_parent
    return a.ring
  else
    silent_arr = {:name => :sequential, :content => silent_arr.ring}
    a = {:name => :sequential, :content => a.ring}
    return [{:name => :timed_parallel, :content => [silent_arr,a], :index => 0, :release => 1.0, :mods => []}].ring
  end
end

define :forge do |symbol,string|
  use_bpm 30
  anvil = parser.parse(string).content
  apply_mods anvil, false
  with_fx :reverb, room: 0.9 do
    with_fx :distortion, distort: 0.9 do
      with_fx :flanger, feedback: 0.2 do
        live_loop symbol do
          use_synth :piano
          play_data_structure anvil
        end
      end
    end
  end
end

# Forge Plan

# Merge plan2 into plan1
define :merge_plan do |plan1,plan2|
  i = 0
  j = 0
  while i < plan1.length
    while j < plan2.length && plan1[i][:time] >= plan2[j][:time]
      if plan1[i][:time] = plan2[j][:time]
        plan1[i][:actions] = plan1[i][:actions] + plan2[j][:actions]
      else
        plan1.insert(i,plan2[j])
      end
      j = j + 1
    end
    i = i + 1
  end
  while j < plan2.length
    plan1 << plan2[j]
    j = j + 1
  end
end

define :plan_anvil_list do |list,steps,index,time,plan|
  with_bpm_mul(steps) do
    steps.times do
      plan_data_structure list[:content][index], time, plan
      time = time + bt(1)
      index = index + 1
    end
  end
end

define :plan_data_structure do |anvil,time,plan|
  case anvil[:name]
  when :sym, :note, :word
    a = anvil.dup
    a[:release] = bt(a[:release])
    plan << { :time => time , :actions => [a] }
  when :sequential
    plan_anvil_list anvil, anvil[:content].length, 0, time, plan
  when :parallel
    density 1/anvil[:release] do
      anvil[:content].each do |list|
        temp_plan = []
        plan_data_structure list, time, temp_plan
        merge_plan plan, temp_plan
      end
    end
  when :timed_parallel
    index = anvil[:index]
    steps = anvil[:content][0][:content].length
    density 1.0/anvil[:release] do
      anvil[:content].each do |list|
        temp_plan = []
        plan_anvil_list list, steps, index, time, temp_plan
        merge_plan plan, temp_plan
      end
    end
    anvil[:index] = anvil[:index] + steps
  end
end

define :play_plan do |plan|
  in_thread do
    i = 0
    while i + 1 < plan.length
      plan[i][:actions].map do |action|
        in_thread do
          play_data_structure action
        end
      end
      sleep plan[i+1][:time] - plan[i][:time]
      i = i + 1
    end
    plan[i][:actions].map do |action|
      in_thread do
        play_data_structure action
      end
    end
    sleep 1.0 - plan[i][:time]
  end
end

define :forge_plan do |string|
  anvil = parser.parse(string).content
  apply_mods anvil, false
  plan = []
  plan_data_structure anvil, 0.0, plan
  return plan
end

define :forge_alt do |string|
  play_plan forge_plan string
end

# Tests

define :valid_anvil? do |anvil|
  assert anvil.is_a? Hash
  assert anvil[:name].is_a? Symbol
  case anvil[:name]
  when :sym
    assert anvil[:content].is_a? Symbol
    assert anvil[:release].is_a? Float
  when :note
    assert anvil[:content].is_a? Float
    assert anvil[:release].is_a? Float
  when :sequential
    assert anvil[:content].is_a? SonicPi::Core::RingVector
    anvil[:content].map do |list|
      assert valid_anvil? list
    end
  when :parallel
    assert anvil[:content].is_a? Array
    anvil[:content].map do |list|
      assert valid_anvil? list
    end
    assert anvil[:release].is_a? Float
  when :timed_parallel
    assert anvil[:index].is_a? Integer
    assert anvil[:content].is_a? Array
    anvil[:content].map do |list|
      assert valid_anvil? list
    end
    assert anvil[:release].is_a? Float
  when :word
    assert anvil[:content].is_a? String
    assert anvil[:release].is_a? Float
  when :silence
  else
    assert false, "Anvil name not recognised - " + anvil[:name].to_s
  end
  return true
end

define :valid_forge_plan? do |forge_plan|
  time = 0.0
  assert forge_plan.is_a? Array
  forge_plan.each do |action|
    assert action.is_a? Hash
    assert action[:time]
    assert time <= action[:time]
    time = action[:time]
    assert action[:actions].is_a? Array
    action[:actions].each do |anvil|
      assert valid_anvil? anvil
    end
  end
  return true
end