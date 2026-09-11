<?php
// Connect with database
session_start();
try {
    $conn = new PDO("mysql:host=localhost;dbname=tax", "root", "");
    $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    die("Connection failed: " . $e->getMessage());
}

if (!isset($_SESSION['user_id'])) {
    // Redirect to login if not logged in
    header("Location: login.php");
    exit();
}

// Check if insert form is submitted
if (isset($_POST["submit"])) {
    // Create table if not already created
    $sql = "CREATE TABLE IF NOT EXISTS faqs (
            id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
            question TEXT NULL,
            answer TEXT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )";

    $statement = $conn->prepare($sql);
    $statement->execute();

    // Insert into faqs table
    $sql = "INSERT INTO faqs (question, answer) VALUES (?, ?)";
    $statement = $conn->prepare($sql);
    $statement->execute([
        $_POST["question"],
        $_POST["answer"]
    ]);
}

// Get all faqs from latest to oldest
$sql = "SELECT * FROM faqs ORDER BY id DESC";
$statement = $conn->prepare($sql);
$statement->execute();
$faqs = $statement->fetchAll();
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Add FAQ - Tax Payment Portal</title>
    <!-- Include Bootstrap CSS -->
    <link rel="stylesheet" type="text/css" href="css/bootstrap.css" />
    <!-- Include Font Awesome from CDN for better icon support -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/5.15.4/css/all.min.css" integrity="sha512-dIawNt8SMI2k2Pr1z6oA6bL3n8AGgUMvQkSNQbI5HdZH3HQOTxFgN3RmbcNYH/qB3d8G7gYJcJ4flNjaA/uZBw==" crossorigin="anonymous" referrerpolicy="no-referrer" />
    <!-- Include Rich Text Editor CSS -->
    <link rel="stylesheet" type="text/css" href="richtext/richtext.min.css" />
    <!-- Custom Enhanced CSS -->
    <style>
        /* General Styles */
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background-color: #f4f6f9;
            color: #333;
        }

        .container {
            max-width: 900px;
            margin: 50px auto;
            background: #ffffff;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 8px 16px rgba(0,0,0,0.1);
        }

        h1 {
            font-size: 2rem;
            color: #000; /* Changed from #007BFF to black */
            margin-bottom: 20px;
        }

        /* Form Styles */
        form {
            margin-bottom: 40px;
        }

        .form-group label {
            font-weight: 600;
            color: #555;
        }

        .form-control {
            border-radius: 5px;
            border: 1px solid #ced4da;
            transition: border-color 0.3s ease;
        }

        .form-control:focus {
            border-color: #007BFF;
            box-shadow: none;
        }

        /* Button Styles */
        .btn-primary, .btn-info, .btn-warning, .btn-danger {
            border-radius: 5px;
            padding: 10px 20px;
            transition: background-color 0.3s ease, border-color 0.3s ease;
            color: #fff !important; /* Set font color to white */
            background-color: #000 !important; /* Set background color to black */
            border-color: #000 !important; /* Set border color to black */
        }

        .btn-primary:hover, .btn-info:hover, .btn-warning:hover, .btn-danger:hover {
            opacity: 0.9;
            color: #fff !important; /* Keep text color white on hover */
            background-color: #333 !important; /* Darker black on hover */
            border-color: #333 !important; /* Darker border on hover */
        }

        /* Specific Button Adjustments (Optional) */
        /* If you want different buttons to have different shades or specific styles, adjust here */

        /* Table Styles */
        table {
            background: #ffffff;
            border-radius: 5px;
            overflow: hidden;
            box-shadow: 0 2px 8px rgba(0,0,0,0.05);
        }

        thead {
            background-color: #000; /* Changed from #007BFF to black */
            color: #ffffff;
        }

        th, td {
            vertical-align: middle !important;
        }

        tbody tr:nth-child(odd) {
            background-color: #f9f9f9;
        }

        .action-buttons a, .action-buttons form {
            display: inline-block;
            margin-right: 5px;
        }

        /* Action Buttons Specific Styles */
        .action-buttons .btn-warning, .action-buttons .btn-danger {
            color: #fff !important; /* Ensure text is white */
            background-color: #000 !important; /* Set background to black */
            border-color: #000 !important; /* Set border to black */
        }

        .action-buttons .btn-warning:hover, .action-buttons .btn-danger:hover {
            background-color: #333 !important; /* Darker black on hover */
            border-color: #333 !important; /* Darker border on hover */
        }

        /* Responsive Adjustments */
        @media (max-width: 768px) {
            .container {
                padding: 20px;
            }

            h1 {
                font-size: 1.5rem;
            }

            .btn {
                width: 100%;
                margin-bottom: 10px;
            }

            .action-buttons form {
                margin-top: 5px;
            }
        }

        /* Rich Text Editor Toolbar Styles */
        /* Override toolbar button colors to black */
        .richText-editor .toolbar .btn {
            color: #000 !important; /* Set icon and text color to black */
            background-color: #f8f9fa !important; /* Optional: Set a light background for better visibility */
            border: 1px solid #ced4da !important; /* Optional: Set border color */
        }

        .richText-editor .toolbar .btn:hover {
            color: #007BFF !important; /* Optional: Change color on hover */
            background-color: #e2e6ea !important; /* Optional: Change background on hover */
        }

        /* Ensure active buttons also have black color */
        .richText-editor .toolbar .btn.active {
            color: #007BFF !important;
            background-color: #e2e6ea !important;
        }

        /* Adjust icons within toolbar buttons to ensure they inherit the correct color */
        .richText-editor .toolbar .btn i {
            color: inherit !important; /* Inherit color from parent .btn */
        }

        /* Optional: Adjust dropdown menus in toolbar */
        .richText-editor .toolbar .dropdown-menu a {
            color: #000 !important;
        }

        .richText-editor .toolbar .dropdown-menu a:hover {
            background-color: #f1f1f1 !important;
            color: #007BFF !important;
        }
    </style>
</head>
<body>
    <!-- Layout for Form to Add FAQ -->
    <div class="container">
        <div class="d-flex justify-content-between align-items-center mb-4">
            <h1>Add FAQ</h1>
            <!-- Button to go to home.php -->
            <a href="home.php" class="btn btn-primary"><i class="fas fa-home"></i> Go to Home</a>
        </div>

        <!-- Form to Add FAQ -->
        <form method="POST" action="add.php">
            <!-- Question -->
            <div class="form-group">
                <label for="question"><i class="fas fa-question-circle"></i> Enter Question</label>
                <input type="text" name="question" id="question" class="form-control" placeholder="Type your question here..." required />
            </div>

            <!-- Answer -->
            <div class="form-group">
                <label for="answer"><i class="fas fa-edit"></i> Enter Answer</label>
                <textarea name="answer" id="answer" class="form-control" placeholder="Type your answer here..." required></textarea>
            </div>

            <!-- Submit Button -->
            <button type="submit" name="submit" class="btn btn-info"><i class="fas fa-plus-circle"></i> Add FAQ</button>
        </form>

        <!-- Show All FAQs Added -->
        <div class="table-responsive">
            <table class="table table-bordered table-hover">
                <!-- Table Heading -->
                <thead>
                    <tr>
                        <th>ID</th>
                        <th>Question</th>
                        <th>Answer</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <!-- Table Body -->
                <tbody>
                    <?php if (count($faqs) > 0): ?>
                        <?php foreach ($faqs as $faq): ?>
                            <tr>
                                <td><?php echo htmlspecialchars($faq["id"]); ?></td>
                                <td><?php echo htmlspecialchars($faq["question"]); ?></td>
                                <td><?php echo nl2br(htmlspecialchars($faq["answer"])); ?></td>
                                <td class="action-buttons">
                                    <!-- Edit Button -->
                                    <a href="edit.php?id=<?php echo urlencode($faq['id']); ?>" class="btn btn-warning btn-sm" title="Edit FAQ">
                                        <i class="fas fa-edit"></i> Edit
                                    </a>
                                    <!-- Delete Form -->
                                    <form method="POST" action="delete.php" onsubmit="return confirm('Are you sure you want to delete this FAQ?');" style="display:inline;">
                                        <input type="hidden" name="id" value="<?php echo htmlspecialchars($faq['id']); ?>" required />
                                        <button type="submit" class="btn btn-danger btn-sm" title="Delete FAQ">
                                            <i class="fas fa-trash-alt"></i> Delete
                                        </button>
                                    </form>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    <?php else: ?>
                        <tr>
                            <td colspan="4" class="text-center">No FAQs available at the moment. Please add some FAQs.</td>
                        </tr>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>
    </div>

    <!-- Include jQuery -->
    <script src="js/jquery-3.3.1.min.js"></script>
    <!-- Include Bootstrap JS -->
    <script src="js/bootstrap.js"></script>
    <!-- Include Rich Text Editor JS -->
    <script src="richtext/jquery.richtext.js"></script>
    <!-- Initialize Rich Text Editor -->
    <script>
        // Initialize rich text library
        window.addEventListener("load", function() {
            $("#answer").richText({
                // Customize the toolbar as needed
                toolbar: [
                    'bold', 'italic', 'underline', 'strike',
                    '|',
                    'fontList', 'fontName', 'fontSize',
                    '|',
                    'color', 'highlight',
                    '|',
                    'alignment',
                    '|',
                    'unorderedList', 'orderedList',
                    '|',
                    'link', 'image', 'video',
                    '|',
                    'html'
                ]
            });
        });
    </script>
</body>
</html>
