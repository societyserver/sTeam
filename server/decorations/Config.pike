inherit "/kernel/decoration";

#define CONFIG_ATTRIBUTE "config"


string get_decoration_class ()
{
  return "Config";
}


mixed get_config ( string key )
{
  return get_configs()[ key ];
}


mapping get_configs ( array|void configs )
{
  mapping config = query_attribute( CONFIG_ATTRIBUTE );
  if ( !mappingp(config) ) return ([ ]);
  else if ( zero_type(configs) || !arrayp(configs) || sizeof(configs) == 0 )
    return config;
  mapping result = ([ ]);
  foreach ( configs, string key )
    result[ key ] = config[ key ];
  return result;
}


mixed set_config ( string key, mixed value )
{
  mapping config = get_configs();
  config[ key ] = value;
  if ( !set_attribute( CONFIG_ATTRIBUTE, config ) ) return UNDEFINED;
  return value;
}


mapping set_configs ( mapping configs )
{
  if ( !set_attribute( CONFIG_ATTRIBUTE, get_configs() | configs ) )
    return UNDEFINED;
  return configs;
}


void remove_config ( string key )
{
  mapping config = get_configs();
  if ( !has_index( config, key ) ) return;
  m_delete( config, key );
  set_attribute( CONFIG_ATTRIBUTE, config );
}


void remove_configs ( array keys )
{
  mapping config = get_configs();
  foreach ( keys, string key )
    m_delete( config, key );
  set_attribute( CONFIG_ATTRIBUTE, config );
}
