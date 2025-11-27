{{- $backendHost := default (printf "%s-web" (include "magento.fullname" .)) .Values.varnish.backendHost -}}
{{- $backendPort := printf "%v" (default .Values.service.port .Values.varnish.backendPort) -}}
{{- $phpSvc := "php-fpm" -}}
{{- $webSvc := printf "%s-web" (include "magento.fullname" .) -}}

# VCL version 5.0 is not supported so it should be 4.0 even though actually used Varnish version is 6
vcl 4.0;

import std;
# The minimal Varnish version is 6.0
# For SSL offloading, pass the following header in your proxy server or load balancer: 'X-Forwarded-Proto: https'

backend default {
    .host = {{ printf "%q" $backendHost }};
    .port = {{ printf "%q" $backendPort }};
    .first_byte_timeout = 600s;
    .probe = {
        .url = "/health_check.php";
        .timeout = 2s;
        .interval = 5s;
        .window = 10;
        .threshold = 5;
   }
}

acl purge {
    "127.0.0.1";
    "localhost";
    {{ printf "%q" $phpSvc }};
    {{ printf "%q" $webSvc }};
    "varnish";
    {{- range $cidr := .Values.varnish.purgeCIDRs }}
    {{ printf "%q" $cidr }};
    {{- end }}
}

sub vcl_recv {
    if (req.restarts > 0) {
        set req.hash_always_miss = true;
    }

    if (req.method == "PURGE") {
        if (client.ip !~ purge) {
            return (synth(405, "Method not allowed"));
        }
        if (!req.http.X-Magento-Tags-Pattern && !req.http.X-Pool) {
            return (synth(400, "X-Magento-Tags-Pattern or X-Pool header required"));
        }
        if (req.http.X-Magento-Tags-Pattern) {
          ban("obj.http.X-Magento-Tags ~ " + req.http.X-Magento-Tags-Pattern);
        }
        if (req.http.X-Pool) {
          ban("obj.http.X-Pool ~ " + req.http.X-Pool);
        }
        return (synth(200, "Purged"));
    }

    if (req.method != "GET" &&
        req.method != "HEAD" &&
        req.method != "PUT" &&
        req.method != "POST" &&
        req.method != "TRACE" &&
        req.method != "OPTIONS" &&
        req.method != "DELETE") {
          return (pipe);
    }

    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    if (req.url ~ "/customer" || req.url ~ "/checkout") {
        return (pass);
    }

    if (req.url ~ "^/(pub/)?(health_check.php)$") {
        return (pass);
    }

    set req.http.grace = "none";

    set req.url = regsub(req.url, "^http[s]?://", "");

    std.collect(req.http.Cookie);

    if (req.url ~ "(\?|&)(gad_source|gbraid|wbraid|_gl|dclid|gclsrc|srsltid|msclkid|gclid|cx|_kx|ie|cof|siteurl|zanpid|origin|fbclid|mc_[a-z]+|utm_[a-z]+|_bta_[a-z]+)=") {
        set req.url = regsuball(req.url, "(gad_source|gbraid|wbraid|_gl|dclid|gclsrc|srsltid|msclkid|gclid|cx|_kx|ie|cof|siteurl|zanpid|origin|fbclid|mc_[a-z]+|utm_[a-z]+|_bta_[a-z]+)=[-_A-z0-9+()%.]+&?", "");
        set req.url = regsub(req.url, "[?|&]+$", "");
    }

    if (req.url ~ "^/(pub/)?(media|static)/") {
        return (pass);
    }

    if (req.url ~ "^/(pub/)?customer/section/load/?") {
        return (pass);
    }

    if (req.url ~ "/graphql" && !req.http.X-Magento-Cache-Id && req.http.Authorization ~ "^Bearer") {
        return (pass);
    }

    return (hash);
}

sub vcl_hash {
    if ((req.url !~ "/graphql" || !req.http.X-Magento-Cache-Id) && req.http.cookie ~ "X-Magento-Vary=") {
        hash_data(regsub(req.http.cookie, "^.*?X-Magento-Vary=([^;]+);*.*$", "\1"));
    }
    if (req.url ~ "/graphql" && req.http.X-Magento-Cache-Id) {
        hash_data(req.http.Authorization);
        hash_data(req.http.X-Magento-Cache-Id);
    }
}

sub vcl_backend_response {
    set beresp.ttl = 4h;
    set beresp.grace = 15m;
    set beresp.keep = 24h;

    if (beresp.http.x-magento-cache-control ~ "static") {
        set beresp.ttl = 4w;
    }

    if (beresp.http.Cache-Control ~ "private" ||
        beresp.http.Authorization ||
        beresp.http.Set-Cookie) {
        set beresp.uncacheable = true;
        set beresp.ttl = 15s;
        return (deliver);
    }

    if (beresp.ttl <= 0s ||
      beresp.status == 404 ||
      beresp.status == 500 ||
      beresp.status == 502 ||
      beresp.status == 503 ||
      beresp.status == 504) {
        set beresp.uncacheable = true;
        set beresp.ttl = 1s;
        return (deliver);
    }

    set beresp.http.grace = "normal (TTL)";
    if (beresp.http.Surrogate-Control ~ "ESI/1.0") {
        unset beresp.http.Surrogate-Control;
        set beresp.do_esi = true;
    }
}

sub vcl_deliver {
    if (req.http.X-Magento-Debug) {
        if (obj.hits > 0) {
            set resp.http.X-Magento-Cache-Debug = "HIT";
            set resp.http.Grace = req.http.grace;
        } else {
            set resp.http.X-Magento-Cache-Debug = "MISS";
            set resp.http.Grace = "miss";
        }
    } else {
        unset resp.http.X-Magento-Debug;
    }

    unset resp.http.X-Magento-Tags;
    unset resp.http.X-Powered-By;
    unset resp.http.Server;
    unset resp.http.Via;
    unset resp.http.Link;
}

sub vcl_hit {
    if (obj.ttl >= 0s) {
        return (deliver);
    }
    if (std.healthy(req.backend_hint)) {
        return (pass);
    }

    if (!std.healthy(req.backend_hint) &&
        (obj.ttl + obj.grace > 0s)) {
        set req.http.grace = "full";
        return (deliver);
    } else {
        return (pass);
    }
}

sub vcl_miss {
    if (req.http.grace ~ "full") {
        return (pass);
    }
}
