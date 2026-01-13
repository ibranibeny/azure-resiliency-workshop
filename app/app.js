require('dotenv').config();
const express = require('express');
const path = require('path');
const sql = require('mssql');
const { v4: uuidv4 } = require('uuid');

const app = express();
const PORT = process.env.PORT || 3000;

// Region identifier - set this via environment variable
const REGION = process.env.REGION || 'Unknown Region';
const REGION_COLOR = process.env.REGION_COLOR || '#6c757d';

// Azure SQL Database configuration (uses Failover Group listener endpoint)
const sqlConfig = {
    server: process.env.SQL_SERVER || 'localhost',
    database: process.env.SQL_DATABASE || 'socialMediaDB',
    user: process.env.SQL_USER || 'sqladmin',
    password: process.env.SQL_PASSWORD || '',
    options: {
        encrypt: process.env.SQL_ENCRYPT !== 'false',
        trustServerCertificate: process.env.SQL_TRUST_SERVER_CERTIFICATE === 'true',
        enableArithAbort: true
    },
    pool: {
        max: 10,
        min: 0,
        idleTimeoutMillis: 30000
    }
};

let pool;
let dbConnected = false;

// Initialize SQL Database connection
async function initSqlDB() {
    try {
        if (!process.env.SQL_SERVER || !process.env.SQL_PASSWORD) {
            console.warn('⚠️  Azure SQL credentials not configured. Running in demo mode with mock data.');
            return false;
        }
        
        pool = await sql.connect(sqlConfig);
        
        // Create table if not exists
        await pool.request().query(`
            IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='posts' AND xtype='U')
            CREATE TABLE posts (
                id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
                userId NVARCHAR(50) NOT NULL,
                username NVARCHAR(100) NOT NULL,
                message NVARCHAR(500) NOT NULL,
                timestamp DATETIME2 DEFAULT GETUTCDATE(),
                region NVARCHAR(50),
                updatedAt DATETIME2 NULL,
                updatedRegion NVARCHAR(50) NULL
            )
        `);
        
        dbConnected = true;
        console.log('✅ Connected to Azure SQL Database');
        console.log(`   Server: ${process.env.SQL_SERVER}`);
        console.log(`   Database: ${process.env.SQL_DATABASE}`);
        return true;
    } catch (error) {
        console.error('❌ Failed to connect to Azure SQL:', error.message);
        return false;
    }
}

// Mock data for demo mode
let mockPosts = [
    {
        id: 'mock-001',
        userId: 'user-001',
        username: 'demo_user',
        message: 'Welcome to the Resiliency Workshop! 🎉',
        timestamp: new Date().toISOString(),
        region: REGION
    }
];

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// Health check endpoint for Azure Front Door
app.get('/health', async (req, res) => {
    let dbStatus = 'disconnected';
    
    if (dbConnected && pool) {
        try {
            await pool.request().query('SELECT 1');
            dbStatus = 'connected';
        } catch (error) {
            dbStatus = 'error';
        }
    } else if (!process.env.SQL_SERVER) {
        dbStatus = 'mock-mode';
    }
    
    res.status(200).json({ 
        status: 'healthy', 
        region: REGION,
        database: dbStatus,
        timestamp: new Date().toISOString()
    });
});

// API endpoint to get region info
app.get('/api/region', (req, res) => {
    res.json({ 
        region: REGION, 
        color: REGION_COLOR,
        timestamp: new Date().toISOString()
    });
});

// Get all posts
app.get('/api/posts', async (req, res) => {
    try {
        if (dbConnected && pool) {
            const result = await pool.request()
                .query('SELECT * FROM posts ORDER BY timestamp DESC');
            res.json(result.recordset);
        } else {
            res.json(mockPosts.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp)));
        }
    } catch (error) {
        console.error('Error fetching posts:', error);
        res.status(500).json({ error: 'Failed to fetch posts' });
    }
});

// Create new post
app.post('/api/posts', async (req, res) => {
    try {
        const { username, message } = req.body;
        
        if (!username || !message) {
            return res.status(400).json({ error: 'Username and message are required' });
        }

        const newPost = {
            id: uuidv4(),
            userId: `user-${uuidv4().substring(0, 8)}`,
            username: username.trim(),
            message: message.trim(),
            timestamp: new Date().toISOString(),
            region: REGION
        };

        if (dbConnected && pool) {
            await pool.request()
                .input('id', sql.UniqueIdentifier, newPost.id)
                .input('userId', sql.NVarChar(50), newPost.userId)
                .input('username', sql.NVarChar(100), newPost.username)
                .input('message', sql.NVarChar(500), newPost.message)
                .input('region', sql.NVarChar(50), newPost.region)
                .query(`
                    INSERT INTO posts (id, userId, username, message, region)
                    VALUES (@id, @userId, @username, @message, @region)
                `);
        } else {
            mockPosts.unshift(newPost);
        }

        res.status(201).json(newPost);
    } catch (error) {
        console.error('Error creating post:', error);
        res.status(500).json({ error: 'Failed to create post' });
    }
});

// Update existing post
app.put('/api/posts/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const { message } = req.body;
        
        if (!message) {
            return res.status(400).json({ error: 'Message is required' });
        }

        if (dbConnected && pool) {
            const result = await pool.request()
                .input('id', sql.UniqueIdentifier, id)
                .input('message', sql.NVarChar(500), message.trim())
                .input('updatedAt', sql.DateTime2, new Date())
                .input('updatedRegion', sql.NVarChar(50), REGION)
                .query(`
                    UPDATE posts 
                    SET message = @message, updatedAt = @updatedAt, updatedRegion = @updatedRegion
                    OUTPUT INSERTED.*
                    WHERE id = @id
                `);
            
            if (result.recordset.length === 0) {
                return res.status(404).json({ error: 'Post not found' });
            }
            
            res.json(result.recordset[0]);
        } else {
            // Mock mode
            const postIndex = mockPosts.findIndex(p => p.id === id);
            if (postIndex === -1) {
                return res.status(404).json({ error: 'Post not found' });
            }
            
            mockPosts[postIndex] = {
                ...mockPosts[postIndex],
                message: message.trim(),
                updatedAt: new Date().toISOString(),
                updatedRegion: REGION
            };
            res.json(mockPosts[postIndex]);
        }
    } catch (error) {
        console.error('Error updating post:', error);
        res.status(500).json({ error: 'Failed to update post' });
    }
});

// Delete a specific post
app.delete('/api/posts/:id', async (req, res) => {
    try {
        const { id } = req.params;

        if (dbConnected && pool) {
            const result = await pool.request()
                .input('id', sql.UniqueIdentifier, id)
                .query('DELETE FROM posts WHERE id = @id');
            
            if (result.rowsAffected[0] === 0) {
                return res.status(404).json({ error: 'Post not found' });
            }
        } else {
            const postIndex = mockPosts.findIndex(p => p.id === id);
            if (postIndex === -1) {
                return res.status(404).json({ error: 'Post not found' });
            }
            mockPosts.splice(postIndex, 1);
        }

        res.json({ message: 'Post deleted successfully' });
    } catch (error) {
        console.error('Error deleting post:', error);
        res.status(500).json({ error: 'Failed to delete post' });
    }
});

// Delete all posts (for demo reset)
app.delete('/api/posts', async (req, res) => {
    try {
        if (dbConnected && pool) {
            await pool.request().query('DELETE FROM posts');
        } else {
            mockPosts = [];
        }
        
        res.json({ message: 'All posts deleted' });
    } catch (error) {
        console.error('Error deleting posts:', error);
        res.status(500).json({ error: 'Failed to delete posts' });
    }
});

// Home page
app.get('/', (req, res) => {
    res.render('index', { 
        region: REGION, 
        regionColor: REGION_COLOR 
    });
});

// Graceful shutdown
process.on('SIGINT', async () => {
    console.log('\n🛑 Shutting down...');
    if (pool) {
        await pool.close();
        console.log('✅ Database connection closed');
    }
    process.exit(0);
});

// Start server
async function startServer() {
    await initSqlDB();
    
    app.listen(PORT, () => {
        console.log(`
╔════════════════════════════════════════════════════════════╗
║     🌐 Social Media App - Resiliency Workshop              ║
╠════════════════════════════════════════════════════════════╣
║  Server running on: http://localhost:${PORT}                   ║
║  Region: ${REGION.padEnd(47)}║
║  Database: ${(dbConnected ? 'Azure SQL (Connected)' : 'Mock Mode').padEnd(45)}║
║  Health Check: http://localhost:${PORT}/health                 ║
╚════════════════════════════════════════════════════════════╝
        `);
    });
}

startServer();
