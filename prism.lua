-- prism v0.1.0
-- ?
--
-- llllllll.co/t/?
--
--
--
--    ▼ instructions below ▼
--
-- ?

s={
  update_ui=false,
  current_time=0,
  v={},-- voices to be initialized in init()
  freqs={},
  recording=false,
}

function init()
  params:add_separator("prism")
  params:add_taper("slew rate","slew rate",0,30,(60/clock.get_tempo()),0,"s")
  params:set_action("slew rate",update_parameters)
  params:add_taper("resolution","resolution",10,200,50,0,"ms")
  params:set_action("resolution",update_parameters)
  params:read(_path.data..'prism/'.."prism.pset")
  
  for i=1,6 do
    s.v[i]={}
    s.v[i].position=0
    s.v[i].midi=0 -- target midi note
    s.v[i].freq=0 -- current frequency
  end
  
  -- initialize timers
  -- initialize timer for updating screen
  timer=metro.init()
  timer.time=params:get("resolution")/1000
  timer.count=-1
  timer.event=update_main
  timer:start()
  
  -- position poll
  softcut.event_phase(update_positions)
  softcut.poll_start_phase()
  
  -- frequency poll
  local pitch_poll_l=poll.set("pitch_in_l",function(value)
    update_freq(value)
  end)
  pitch_poll_l:start()
  
  -- amplitude poll
  p_amp_in=poll.set("amp_in_l")
  p_amp_in.time=params:get("resolution")/1000
  p_amp_in.callback=function(val)
    -- TODO: toggle recording
  end
  p_amp_in:start()
  
  -- watch midi
  midi_signal_in=midi.connect(1)
  midi_signal_in.event=update_midi
  
  -- initialize softcut
  for i=1,6 do
    if i==1 then
      -- voice 1 records into buffer, but does not play
      softcut.level(i,0)
      softcut.level_input_cut(1,i,1)
      softcut.level_input_cut(2,i,1)
      softcut.rec_level(i,1)
      softcut.pre_level(i,0)
    else
      softcut.level(i,1)
      softcut.level_input_cut(1,i,0)
      softcut.level_input_cut(2,i,0)
    end
    softcut.pan(i,0)
    softcut.play(i,0)
    softcut.rate(i,1)
    softcut.loop_start(i,0)
    softcut.loop_end(i,120)
    softcut.loop(i,1)
    softcut.rec(i,0)
    
    softcut.fade_time(i,0.2)
    softcut.level_slew_time(i,params:get("resolution")/1000)
    softcut.rate_slew_time(i,params:get("resolution")/1000)
    
    softcut.buffer(i,1)
    softcut.position(i,0)
    softcut.enable(i,1)
    softcut.phase_quant(i,params:get("resolution")/1000/2)
  end
end

--
-- updaters
--
function update_parameters(x)
  params:write(_path.data..'prism/'.."prism.pset")
end

function update_positions(i,x)
  s.v[i].position=x
end

function update_freq(f)
  if s.recording then
    s.freqs[round_to_nearest(s.v[1].position,params:get("resolution")/1000)]=f
  end
end

function update_main()
  s.current_time=s.current_time+params:get("resolution")/1000
  if s.update_main then
    redraw()
  end
  for i=1,6 do
    if s.v[i].midi>0 then
      -- TODO: modulate the voice's rate to match upcoming pitch
      -- TODO: if midi is higher then pitch, then find the next octave down
    end
  end
end

function update_midi(data)
  msg=midi.to_msg(data)
  if msg.type=='note_on' then
    print(msg.note,msg.vel/127.0)
    -- find first available voice and turn it on
    for i=1,6 do
      if s.v[i].midi==0 then
        s.v[i].midi=msg.note
        break
      end
    end
  elseif msg.type=='note_off' then
    -- turn off any voices on that note
    for i=1,6 do
      if s.v[i].midi==msg.note then
        s.v[i].midi=0
      end
    end
  end
end

--
-- screen
--
function redraw()
  s.update_ui=false
  screen.clear()
  screen.update()
end

--
-- utils
--
function round(x)
  return x>=0 and math.floor(x+0.5) or math.ceil(x-0.5)
end

function sign(x)
  if x>0 then
    return 1
  elseif x<0 then
    return-1
  else
    return 0
  end
end

function round_to_nearest(x,yth)
  remainder=x%yth
  if remainder==0 then
    return x
  end
  return x+yth-remainder
end

function midi_to_hz(note)
  return (440/32)*(2^((note-9)/12))
end
