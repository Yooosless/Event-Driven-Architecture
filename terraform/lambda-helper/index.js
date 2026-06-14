const https = require('https');

exports.handler = async (event) => {
    const payload = typeof event.body === 'string' ? event.body : JSON.stringify(event.body || {});
    
    const headers = event.headers || {};
    const originSource = headers['X-Source'] || headers['x-source'] || 'UNKNOWN';
    const ec2Address = process.env.EC2_PUBLIC_IP;

    const options = {
        hostname: ec2Address,
        port: 443,
        path: '/send',
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-Source': originSource,
            'Content-Length': Buffer.byteLength(payload)
        },
        rejectUnauthorized: false 
    };

    return new Promise((resolve) => {
        const req = https.request(options, (res) => {
            let body = '';
            res.on('data', (chunk) => body += chunk);
            res.on('end', () => {
                resolve({
                    statusCode: 200,
                    body: JSON.stringify({ status: "Forwarded cleanly!", remoteCode: res.statusCode })
                });
            });
        });

        req.on('error', (err) => {
            console.error("Routing exception encountered across cloud path:", err);
            resolve({
                statusCode: 500,
                body: JSON.stringify({ error: "Cannot route payload back to central core", details: err.message })
            });
        });

        req.write(payload);
        req.end();
    });
};