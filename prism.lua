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
  loop_end=0,
}

function init()
  params:add_separator("prism")
  params:add_taper("slew rate","slew rate",0,30,(60/clock.get_tempo()),0,"s")
  params:set_action("slew rate",update_parameters)
  params:add_taper("resolution","resolution",10,200,50,0,"ms")
  params:set_action("resolution",update_parameters)
  params:add_control("rec thresh","rec thresh",controlspec.new(1,100,'exp',1,10,'amp/1k'))
  params:set_action("rec thresh",update_parameters)
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
    -- toggle recording
    if val>params:get("rec thresh")/1000 then
      softcut.rec(1,1)
      softcut.play(1,1)
      s.recording=true
    else
      s.recording=false
      softcut.rec(1,0)
      softcut.play(1,0)
      softcut.position(1,0)
      s.loop_end=s.v[1].position
    end
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
  -- make sure to check to see if current position
  -- of voice 1 went back to 0 and, if so,
  -- reset all other loop starts
  if i==1 and x<s.v[i].position then
    for j=2,6 do
      softcut.loop_start(j,0)
      softcut.loop_end(j,x)
    end
  end
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
      -- modulate the voice's rate to match upcoming pitch
      next_position=round_to_nearest(s.v[i].position+params:get("resolution")/1000,params:get("resolution")/1000)
      if s.freqs[next_position]~=nil then
        next_freq=s.freqs[next_position]
        target_freq=s.v[i].freq
        softcut.rate(i,target_freq/next_freq)
        if s.recording then
          softcut.loop_end(i,s.v[1].position)
        end
      end
    end
  end
end

function update_midi(data)
  msg=midi.to_msg(data)
  if msg.type=='note_on' then
    print(msg.note,msg.vel/127.0)
    -- find first available voice and turn it on
    for i=2,6 do
      if s.v[i].midi==0 then
        s.v[i].midi=msg.note
        s.v[i].freq=midi_to_hz(msg.note)
        -- move to current position of recording
        s.v[i].position=s.v[1].position
        softcut.position(i,s.v[1].position)
        softcut.play(i,1)
        break
      end
    end
  elseif msg.type=='note_off' then
    -- turn off any voices on that note
    for i=2,6 do
      if s.v[i].midi==msg.note then
        s.v[i].midi=0
        s.v[i].freq=0
        softcut.play(i,0)
        softcut.rate(i,0)
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
