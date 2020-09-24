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

function init()
  params:add_separator("oooooo")
  -- add variables into main menu
  
  params:add_group("startup",4)
  params:add_option("load on start","load on start",{"no","yes"},1)
  params:set_action("load on start",update_parameters)
  params:add_option("play on start","play on start",{"no","yes"},1)
  params:set_action("play on start",update_parameters)
  params:add_option("start lfos random","start lfos random",{"no","yes"},1)
  params:set_action("start lfos random",update_parameters)
  params:add_control("start length","start length",controlspec.new(0,64,'lin',1,0,'beats'))
  params:set_action("start length",update_parameters)
end
