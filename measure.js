const http = require('http');

function makeRequest() {
    return new Promise((resolve) => {
        const options = {
            hostname: 'lb-eks-bug-521316508.us-west-1.elb.amazonaws.com',
            port: 80,
            path: '/',
            method: 'GET',
            headers: {
                'Host': 'example.customdomain.com'
            },
            timeout: 5000
        };

        const req = http.request(options, (res) => {
            resolve(res.statusCode === 200);
        });

        req.on('error', () => {
            resolve(false);
        });

        req.on('timeout', () => {
            req.destroy();
            resolve(false);
        });

        req.end();
    });
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function calculateStats(successful, failed, total) {
    const successRate = (successful / total) * 100;
    const failureRate = (failed / total) * 100;
    return {
        successRate: successRate.toFixed(1),
        failureRate: failureRate.toFixed(1)
    };
}

async function main() {
    const totalRequests = 300;
    let successful = 0;
    let failed = 0;

    console.log(`Starting ${totalRequests} requests (1 per second)...`);

    for (let i = 0; i < totalRequests; i++) {
        const currentRequestNum = i + 1;
        process.stdout.write(`Making request ${currentRequestNum}/${totalRequests} `);

        const isSuccess = await makeRequest();

        if (isSuccess) {
            successful++;
        } else {
            failed++;
        }

        const stats = calculateStats(successful, failed, currentRequestNum);
        console.log(`[Success: ${stats.successRate}%, Failed: ${stats.failureRate}%] - ${isSuccess ? 'SUCCESS' : 'FAILED'}`);

        if (i < totalRequests - 1) {
            await sleep(1000);
        }
    }

    const finalStats = calculateStats(successful, failed, totalRequests);
    console.log('\nFinal Summary:');
    console.log(`Successful requests: ${successful} (${finalStats.successRate}%)`);
    console.log(`Failed requests: ${failed} (${finalStats.failureRate}%)`);
}

main().catch(console.error);