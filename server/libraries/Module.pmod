mapping read_config(string cfg_data, string rtag)
{
  //TODO: this is just a wrapper. All read_config() calls in modules should be replaced by Config.get_config( cfg_data, rtag )
  return Config.get_config( cfg_data, rtag );
}
