<?php
$CONFIG = [
  'trusted_domains' => ['integrac.unterhaken.at', 'integrac.k8s.unterhaken.at', 'nextcloud.integrac.svc.cluster.local'],
  'trusted_proxies' => ['10.42.0.0/16'],
  'overwriteprotocol' => 'https',
  'overwrite.cli.url' => 'https://integrac.unterhaken.at',
  'htaccess.RewriteBase' => '/',
  'apps_paths' => [
    ['path' => '/var/www/html/apps', 'url' => '/apps', 'writable' => false],
    ['path' => '/var/www/html/custom_apps', 'url' => '/custom_apps', 'writable' => true],
  ],
  'memcache.local' => '\OC\Memcache\APCu',
  'memcache.distributed' => '\OC\Memcache\Redis',
  'memcache.locking' => '\OC\Memcache\Redis',
  'redis' => ['host' => '127.0.0.1', 'port' => 6379],
  'log_type' => 'errorlog',
  'loglevel' => 2,
  'default_phone_region' => 'AT',
  'maintenance_window_start' => 1,
];
