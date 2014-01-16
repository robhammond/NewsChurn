// initialise casper
var casper = require("casper").create({
    viewportSize: {
        width: 1024,
        height: 768
    }
});

// set user agent
casper.userAgent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:25.0) Gecko/20100101 Firefox/25.0');

// get contact url & db id number via CLI input
var url		= casper.cli.get("url");
var id		= casper.cli.get("id");

// start user agent
casper.start(url, function() {
    this.capture('screengrabs/' + id + '.jpg', undefined, {
        format: 'jpg',
        quality: 70
    });
});

casper.run();