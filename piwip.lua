-- piwip v0.1.0
-- ?
--
-- llllllll.co/t/?
--
--
--
--    ▼ instructions below ▼
--
-- ?

-- state variable
s={
  v={},-- voices to be initialized in init()
  freqs={},-- stores frequency information
  update_ui=false,-- toggles redraw
  recording=false,-- recording state
  loop_end=0,-- amount recorded into buffer
  silence_time=0,-- amount of silence (during recording)
}

function init()
  params:add_separator("prism")
  params:add_taper("slew rate","slew rate",0,30,(60/clock.get_tempo()),0,"s")
  params:set_action("slew rate",update_parameters)
  params:add_taper("resolution","resolution",10,200,50,0,"ms")
  params:set_action("resolution",update_parameters)
  params:add_control("rec thresh","rec thresh",controlspec.new(1,100,'exp',1,10,'amp/1k'))
  params:set_action("rec thresh",update_parameters)
  params:add_taper("debounce time","debounce time",10,500,200,0,"ms")
  params:set_action("debounce time",update_parameters)
  params:add_taper("min recorded","min recorded",10,1000,60,0,"ms")
  params:set_action("min recorded",update_parameters)
  params:read(_path.data..'prism/'.."prism.pset")
  
  for i=1,6 do
    s.v[i]={}
    s.v[i].position=0
    s.v[i].midi=0 -- target midi note
    s.v[i].freq=0 -- current frequency
    s.v[i].loop_end=0
    s.v[i].started=false
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
  
  -- frequency poll (average l+r channels)
  local pitch_poll_l=poll.set("pitch_in_l",function(value)
    update_freq(value)
  end)
  pitch_poll_l:start()
  local pitch_poll_r=poll.set("pitch_in_r",function(value)
    update_freq(value)
  end)
  pitch_poll_r:start()
  
  -- amplitude poll
  p_amp_in=poll.set("amp_in_l")
  p_amp_in.time=params:get("resolution")/1000
  p_amp_in.callback=update_amp
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
    softcut.rec(i,0)
    softcut.rate(i,1)
    softcut.loop_start(i,0)
    softcut.loop_end(i,300)
    softcut.loop(i,1)
    
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
  -- keep track of bounds of recording
  if i==1 and s.recording then
    s.loop_end=x
  end
  s.v[i].position=x
end

function update_freq(f)
  -- ignore frequencies below 30 hz
  if s.recording and f>30 then
    current_position=string.format("%.3f",round_to_nearest(s.v[1].position,params:get("resolution")/1000))
    if s.freqs[current_position]~=nil then
      s.freqs[current_position]=(s.freqs[current_position]+f)/2
    else
      s.freqs[current_position]=f
      print(current_position,f)
    end
  end
end

function update_main()
  if s.update_main then
    redraw()
  end
  -- check active voices and match their pitch using rate
  for i=2,6 do
    -- skip if not playing
    if s.v[i].midi==0 then goto continue end
    
    -- make sure there is a little bit of recorded material
    if s.loop_end<params:get("min recorded")/1000 then goto continue end
    
    -- make sure its bounded by recorded material
    if s.loop_end~=s.v[i].loop_end then
      softcut.loop_end(i,s.loop_end)
    end
    
    -- modulate the voice's rate to match upcoming pitch
    -- find the closest pitch
    for j=2,-5,-1 do
      next_position=round_to_nearest(s.v[i].position+j*params:get("resolution")/1000,params:get("resolution")/1000)
      if s.freqs[next_position]~=nil then
        break
      end
    end
    if s.freqs[next_position]==nil then
	    print("voice "..i.." no freqs found at pos "..s.v[i].position)
	    goto continue 
    end
    
    print("updating rate")
    print(s.v[i].freq,s.freqs[next_position])
    
    -- initialize the voice playing
    if s.v[i].started==false then
      print("starting "..i)
      s.v[i].started=true
      softcut.position(i,util.clamp(s.v[1].position-params:get("min recorded")/1000,0,s.loop_end))
      softcut.play(i,1)
      softcut.level(i,1)
    end
    
    -- update the rate to match correclty modulate upcoming pitch
    softcut.rate(i,s.v[i].freq/s.freqs[next_position])
    ::continue::
  end
end

function update_amp(val)
  -- toggle recording on with incoming amplitude
  -- toggle recording off with silence
  if val>params:get("rec thresh")/1000 then
    -- reset silence time
    s.silence_time=0
    if not s.recording then
      print("init recording")
      softcut.position(1,0)
      softcut.rec(1,1)
      softcut.play(1,1)
      softcut.loop_end(1,300)
      s.freqs={}
      s.recording=true
      s.loop_end=1
      -- reset positions of all current notes
      for i=2,6 do
        softcut.position(i,0)
        softcut.level(i,0)
        s.v[i].started=false
      end
    end
  elseif s.recording then
    -- not above threshold, should add to silence time
    -- to eventually trigger stop recording
    s.silence_time=s.silence_time+params:get("resolution")/1000
    if s.silence_time>params:get("debounce time")/1000 then
      print("stop recording")
      s.recording=false
      softcut.rec(1,0)
      softcut.play(1,0)
      softcut.position(1,0)
      s.loop_end=s.v[1].position-(params:get("debounce time")/1000)
    end
  end
end

function update_midi(data)
  msg=midi.to_msg(data)
  if msg.type=='note_on' then
    -- find first available voice and turn it on
    -- it will be initialized in update_main
    for i=2,6 do
      if s.v[i].midi==0 then
        print("voice "..i.." "..msg.note.." on")
        s.v[i].midi=msg.note
        s.v[i].freq=midi_to_hz(msg.note)
        break
      end
    end
  elseif msg.type=='note_off' then
    -- turn off any voices on that note
    for i=2,6 do
      if s.v[i].midi==msg.note then
        print("voice "..i.." "..msg.note.." off")
        s.v[i].midi=0
        s.v[i].freq=0
        s.v[i].started=false
        softcut.play(i,0)
        softcut.rate(i,0)
        softcut.position(i,0)
        softcut.level(i,0)
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
