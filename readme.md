# Delorme-2-Tumblr

Delomre-2-Tumblr is a ruby script that grabs the Delorme MapShare KML and creates a Tumblr post.

In particular, it does the following
* Pulls the Delorme MapShare KML feed
* Extracts the points
* Creates an image based on the KML
* Gets the current weather coniction and forecast based upon the last point
* Posts a blog entry on Tumblr

## Setting up the script

The following items have to be in your enviroment 

## Configuration

Google Maps
```
export GOOGLE_MAPS_API_KEY="------"
```

Tumblr API
```
export TUMBLR_CONSUMER_KEY="="------""
export TUMBLR_CONSUMER_SECRET="="------""
export TUMBLR_OAUTH_TOKEN="="------""
export TUMBLR_OAUTH_TOKEN_SECRET="="------""
```

Tumbr Blog
```
export TUMBLR_HIKER_NAME="="------""
export TUMBLR_ACCOUNT="="------""
```

Delorme MapShare KML Feed
```
export DELORME_INREACH_MAPSHARE="="------""
export DELORME_INREACH_MAPSHARE_ACCOUNT="="------""
export DELORME_INREACH_MAPSHARE_PASSWORD="="------""
```

Forecast IO API
```
export FORECAST_IO_API_KEY="="------""
```
