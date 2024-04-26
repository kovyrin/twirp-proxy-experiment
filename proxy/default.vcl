vcl 4.1;

# We need these to be able to cache POST requests
import std;
import bodyaccess;

# Point this at the API server
backend default {
    .host = "127.0.0.1";
    .port = "3001";
}

sub vcl_recv {
    unset req.http.x-request-id;

    set req.http.x-method = req.method;
    unset req.http.x-attempt-to-cache-post;

    # Check for no-cache directives in client request and force a miss for those
    if (req.http.Cache-Control ~ "no-cache" || req.http.Cache-Control ~ "max-age=0") {
        std.log("Forcing a cache miss due to no-cache directive");
        set req.hash_always_miss = true;
    }

    # Check for no-store directives in client request and pass those through
    if (req.http.Cache-Control ~ "no-store") {
        std.log("Passing request through due to no-store directive");
        return(pass);
    }

    # Handling max-age value from the client
    if (req.http.Cache-Control ~ "max-age=(\d+)") {
        set req.http.x-cache-max-age = regsub(req.http.Cache-Control, ".*max-age=(\d+).*", "\1");
        std.log("Client requested max-age=" + req.http.x-cache-max-age);
    }

    # Handling stale-while-revalidate value from the client
    if (req.http.Cache-Control ~ "stale-while-revalidate=(\d+)") {
        set req.http.x-cache-stale-while-revalidate = regsub(req.http.Cache-Control, ".*stale-while-revalidate=(\d+).*", "\1");
        std.log("Client requested stale-while-revalidate=" + req.http.x-cache-stale-while-revalidate);
    }

    # Allow POST requests to be cached
    if (req.method == "POST") {
        std.log("Attempting to cache a POST request: " + req.url);
        set req.http.x-attempt-to-cache-post = "1";
        if (std.cache_req_body(500KB)) {
            return(hash);
        }
    }
}

sub vcl_hash {
    if (req.http.x-attempt-to-cache-post) {
        std.log("Hashing a POST body");
        bodyaccess.hash_req_body();
    }
}

sub vcl_backend_fetch {
    # Set the method to the original value to make sure we pass POST requests to the backend
    set bereq.method = bereq.http.x-method;
}

sub vcl_backend_response {
    if (beresp.ttl > 0s) {
        if (bereq.http.x-cache-max-age) {
            std.log("Setting TTL to the client-provided value: " + bereq.http.x-cache-max-age + "s");
            set beresp.ttl = std.duration(bereq.http.x-cache-max-age + "s", 0s);
        } else {
            std.log("Default TTL value of 2 minutes");
            set beresp.ttl = 120s;
        }

        if (bereq.http.x-cache-stale-while-revalidate) {
            std.log("Setting grace to the client-provided value: " + bereq.http.x-cache-stale-while-revalidate + "s");
            set beresp.grace = std.duration(bereq.http.x-cache-stale-while-revalidate + "s", 0s);
        } else {
            std.log("Setting grace to 0s to prevent serving stale content");
            set beresp.grace = 0s;
        }

        # Set the keep time to 7 days to prevent the cache from being purged too soon
        set beresp.keep = 7d;
    }
}
