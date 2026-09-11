<?php
session_start();
include("connect.php");

// Check if user is logged in, otherwise redirect to login page
if (!isset($_SESSION['user_id'])) {
    header("Location: login.php");
    exit();
}

$user_id = $_SESSION['user_id'];
$username = $_SESSION['first_name'];
//$email = $_SESSION['email'];

$sql = "SELECT asset_id, land_type, land_amount, vehicle_type, vehicle_model, business_asset FROM user_assets WHERE user_id = ?";
$stmt = $conn->prepare($sql);
$stmt->bind_param("i", $user_id);
$stmt->execute();
$result = $stmt->get_result();

if (isset($_POST['add_asset'])) {
    $land_type = $_POST['land_type'];
    $land_amount = $_POST['land_amount'];
    $vehicle_type = $_POST['vehicle_type'];
    $vehicle_model = $_POST['vehicle_model'];
    $business_asset = $_POST['business_asset'];

    $insert_sql = "INSERT INTO user_assets (user_id, land_type, land_amount, vehicle_type, vehicle_model, business_asset) 
                   VALUES (?, ?, ?, ?, ?, ?)";
    $stmt_insert = $conn->prepare($insert_sql);
    $stmt_insert->bind_param("isssss", $user_id, $land_type, $land_amount, $vehicle_type, $vehicle_model, $business_asset);
    $stmt_insert->execute();

    // Reload the page to reflect the new asset
    header("Location: asset_details.php");
    exit();
}

// Check if form was submitted to update an existing asset
if (isset($_POST['edit_asset'])) {
    $asset_id = $_POST['asset_id'];
    $land_type = $_POST['land_type'];
    $land_amount = $_POST['land_amount'];
    $vehicle_type = $_POST['vehicle_type'];
    $vehicle_model = $_POST['vehicle_model'];
    $business_asset = $_POST['business_asset'];

    // Update the existing asset in the database
    $update_sql = "UPDATE user_assets SET land_type = ?, land_amount = ?, vehicle_type = ?, vehicle_model = ?, business_asset = ? WHERE asset_id = ? AND user_id = ?";
    $stmt_update = $conn->prepare($update_sql);
    $stmt_update->bind_param("ssssssi", $land_type, $land_amount, $vehicle_type, $vehicle_model, $business_asset, $asset_id, $user_id);
    $stmt_update->execute();

    // Reload the page to reflect the updated asset
    header("Location: asset_details.php");
    exit();
}

// Handle the delete asset request
if (isset($_POST['delete_asset'])) {
    $asset_id = $_POST['asset_id'];

    // Delete the asset from the database
    $delete_sql = "DELETE FROM user_assets WHERE asset_id = ? AND user_id = ?";
    $stmt_delete = $conn->prepare($delete_sql);
    $stmt_delete->bind_param("ii", $asset_id, $user_id);
    $stmt_delete->execute();

    // Return a JSON response
    echo json_encode(['success' => true]);
    exit();
}

// Fetch asset details for editing if an ID is provided
if (isset($_GET['id'])) {
    $asset_id = $_GET['id'];

    // Fetch asset details from the database
    $sql = "SELECT * FROM user_assets WHERE asset_id = ? AND user_id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("ii", $asset_id, $user_id);
    $stmt->execute();
    $result = $stmt->get_result();

    if ($result->num_rows > 0) {
        echo json_encode($result->fetch_assoc());
    } else {
        echo json_encode(['error' => 'No asset found.']);
    }

    $stmt->close();
    exit(); // Prevent further output
}

// Close the statement
$stmt->close();

// Close the connection
$conn->close();
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>User Assets - TaxEase</title>
    <!-- Google Fonts -->
    <link href="https://fonts.googleapis.com/css?family=Open+Sans:400,600,700&display=swap" rel="stylesheet">
    <!-- Font Awesome for Icons -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <!-- Bootstrap CSS (Optional for additional styling) -->
    <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.0/css/bootstrap.min.css">
    <style>
        /* Reset some default browser styles */
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        /* Body styling */
        body {
            font-family: 'Open Sans', sans-serif;
            background-color: #f4f4f9; /* Light gray background */
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            padding: 20px;
        }

        /* Container for the page */
        .container {
            width: 100%;
            max-width: 1000px;
            background-color: #ffffff; /* White background */
            box-shadow: 0 8px 25px rgba(0, 0, 0, 0.1);
            border-radius: 15px;
            padding: 30px;
        }

        /* Header Styles */
        .container h1 {
            text-align: center;
            color: #333333;
            margin-bottom: 10px;
            font-size: 32px;
            font-weight: 700;
        }

        .container p {
            text-align: center;
            color: #555555;
            margin-bottom: 30px;
            font-size: 18px;
        }

        /* Back to Dashboard Button */
        #dashboardBtn {
            display: block;
            margin: 0 auto 20px auto;
            padding: 10px 25px;
            background-color: #007bff; /* Blue background */
            color: white;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            transition: background-color 0.3s ease;
            font-size: 16px;
            font-weight: 600;
        }

        #dashboardBtn:hover {
            background-color: #0056b3; /* Darker blue on hover */
        }

        /* Table Styles */
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 30px;
        }

        table, th, td {
            border: 1px solid #ddd;
        }

        th, td {
            padding: 15px;
            text-align: center;
            color: #333333;
            font-size: 16px;
        }

        /* Table Header Styles */
        thead th {
            background-color: #343a40; /* Dark gray background */
            color: white;
            text-transform: uppercase;
            font-weight: 700;
            font-size: 14px;
        }

        /* Table Row Styles */
        tbody tr:nth-child(even) {
            background-color: #f9f9f9;
        }

        tbody tr:hover {
            background-color: #f1f1f1;
        }

        /* Action Buttons */
        .edit-btn, .delete-btn {
            padding: 8px 12px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 14px;
            transition: background-color 0.3s ease;
            margin: 2px;
        }

        .edit-btn {
            background-color: #ffc107; /* Yellow */
            color: white;
        }

        .edit-btn:hover {
            background-color: #e0a800; /* Darker yellow */
        }

        .delete-btn {
            background-color: #dc3545; /* Red */
            color: white;
        }

        .delete-btn:hover {
            background-color: #c82333; /* Darker red */
        }

        /* Add New Asset Button */
        #addAssetBtn {
            display: block;
            margin: 0 auto;
            padding: 12px 25px;
            background-color: #28a745; /* Green background */
            color: white;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            transition: background-color 0.3s ease;
            font-size: 16px;
            font-weight: 600;
        }

        #addAssetBtn:hover {
            background-color: #218838; /* Darker green on hover */
        }

        /* Modal Styles */
        #assetModal, #editAssetModal {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background-color: rgba(0, 0, 0, 0.6);
            justify-content: center;
            align-items: center;
            z-index: 1000;
        }

        .modal-content {
            background-color: #ffffff;
            padding: 30px;
            border-radius: 10px;
            width: 90%;
            max-width: 600px;
            box-shadow: 0 8px 25px rgba(0, 0, 0, 0.3);
            position: relative;
            animation: fadeIn 0.3s ease;
        }

        /* Close Button */
        #closeModal, #closeEditModal {
            position: absolute;
            top: 15px;
            right: 20px;
            font-size: 24px;
            font-weight: bold;
            color: #555555;
            cursor: pointer;
            transition: color 0.3s ease;
        }

        #closeModal:hover, #closeEditModal:hover {
            color: #000000;
        }

        /* Form Styling */
        .form-field {
            margin-bottom: 20px;
            position: relative;
        }

        .form-field label {
            position: absolute;
            top: -10px;
            left: 15px;
            background-color: #ffffff;
            padding: 0 5px;
            font-size: 14px;
            color: #555555;
            font-weight: 600;
        }

        .form-field input, 
        .form-field select {
            width: 100%;
            padding: 12px 15px;
            font-size: 16px;
            border: 1px solid #ccc;
            border-radius: 5px;
            box-sizing: border-box;
            transition: border-color 0.3s ease, box-shadow 0.3s ease;
        }

        .form-field input:focus, 
        .form-field select:focus {
            border-color: #007bff;
            box-shadow: 0 0 5px rgba(0, 123, 255, 0.5);
            outline: none;
        }

        /* Submit Button */
        .submit-btn {
            width: 100%;
            padding: 12px 20px;
            background-color: #28a745; /* Green background */
            color: white;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 16px;
            font-weight: 600;
            transition: background-color 0.3s ease;
        }

        .submit-btn:hover {
            background-color: #218838; /* Darker green on hover */
        }

        /* Responsive Adjustments */
        @media (max-width: 768px) {
            .container {
                width: 95%;
                padding: 20px;
            }

            .modal-content {
                padding: 20px;
            }

            #dashboardBtn, #addAssetBtn {
                width: 100%;
            }

            .edit-btn, .delete-btn {
                padding: 6px 10px;
                font-size: 12px;
            }
        }

        /* Animation */
        @keyframes fadeIn {
            from { opacity: 0; transform: scale(0.9); }
            to { opacity: 1; transform: scale(1); }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>User Assets</h1>
        <p>Welcome, <?php echo htmlspecialchars($username); ?>!</p>
        <button id="dashboardBtn" onclick="window.location.href='dashboard2.php'">Back to Dashboard</button>
        
        <table>
            <thead>
                <tr>
                    <th>Land Type</th>
                    <th>Land Amount</th>
                    <th>Vehicle Type</th>
                    <th>Vehicle Model</th>
                    <th>Business Asset</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                <?php if ($result->num_rows > 0): ?>
                    <?php while ($row = $result->fetch_assoc()): ?>
                    <tr>
                        <td><?php echo htmlspecialchars($row['land_type']); ?></td>
                        <td><?php echo htmlspecialchars($row['land_amount']); ?></td>
                        <td><?php echo htmlspecialchars($row['vehicle_type']); ?></td>
                        <td><?php echo htmlspecialchars($row['vehicle_model']); ?></td>
                        <td><?php echo htmlspecialchars($row['business_asset']); ?></td>
                        <td>
                            <button class="edit-btn" onclick="editAsset(<?php echo $row['asset_id']; ?>)">
                                <i class="fas fa-edit"></i> Edit
                            </button>
                            <button class="delete-btn" onclick="deleteAsset(<?php echo $row['asset_id']; ?>)">
                                <i class="fas fa-trash-alt"></i> Delete
                            </button>
                        </td>
                    </tr>
                    <?php endwhile; ?>
                <?php else: ?>
                    <tr>
                        <td colspan="6">No assets found. Please add a new asset.</td>
                    </tr>
                <?php endif; ?>
            </tbody>
        </table>

        <button id="addAssetBtn">Add New Asset</button>
    </div>

    <!-- Add Asset Modal -->
    <div id="assetModal">
        <div class="modal-content">
            <span id="closeModal">&times;</span>
            <h2>Add New Asset</h2>
            <form method="POST" action="">
                <div class="form-field">
                    <label for="land_type">Land Type</label>
                    <select id="land_type" name="land_type" required>
                        <option value="">Select land type</option>
                        <option value="Agricultural">Agricultural</option>
                        <option value="Commercial">Commercial</option>
                        <option value="Residential">Residential</option>
                        <option value="N/A">N/A</option>
                    </select>
                </div>

                <div class="form-field">
                    <label for="land_amount">Land Amount (in acres or square meters)</label>
                    <input id="land_amount" name="land_amount" type="number" step="0.01" placeholder="Enter land amount or leave blank for 0">
                </div>

                <div class="form-field">
                    <label for="vehicle_type">Vehicle Type</label>
                    <select id="vehicle_type" name="vehicle_type" required>
                        <option value="">Select vehicle type</option>
                        <option value="Car">Car</option>
                        <option value="Motorcycle">Motorcycle</option>
                        <option value="Truck">Truck</option>
                        <option value="N/A">N/A</option>
                    </select>
                </div>

                <div class="form-field">
                    <label for="vehicle_model">Vehicle Model</label>
                    <select id="vehicle_model" name="vehicle_model" required>
                        <option value="">Select vehicle model</option>
                        <option value="Toyota">Toyota</option>
                        <option value="Honda">Honda</option>
                        <option value="BMW">BMW</option>
                        <option value="N/A">N/A</option>
                    </select>
                </div>

                <div class="form-field">
                    <label for="business_asset">Business Asset</label>
                    <select id="business_asset" name="business_asset" required>
                        <option value="">Select business asset</option>
                        <option value="Shop">Shop</option>
                        <option value="Company">Company</option>
                        <option value="Factory">Factory</option>
                        <option value="N/A">N/A</option>
                    </select>
                </div>

                <button class="submit-btn" type="submit" name="add_asset">Submit</button>
            </form>
        </div>
    </div>

    <!-- Edit Asset Modal -->
    <div id="editAssetModal">
        <div class="modal-content">
            <span id="closeEditModal">&times;</span>
            <h2>Edit Asset</h2>
            <form method="POST" action="">
                <input type="hidden" id="asset_id" name="asset_id" value="">
                
                <div class="form-field">
                    <label for="edit_land_type">Land Type</label>
                    <select id="edit_land_type" name="land_type" required>
                        <option value="">Select land type</option>
                        <option value="Agricultural">Agricultural</option>
                        <option value="Commercial">Commercial</option>
                        <option value="Residential">Residential</option>
                        <option value="N/A">N/A</option>
                    </select>
                </div>

                <div class="form-field">
                    <label for="edit_land_amount">Land Amount (in acres or square meters)</label>
                    <input id="edit_land_amount" name="land_amount" type="number" step="0.01" placeholder="Enter land amount or leave blank for 0">
                </div>

                <div class="form-field">
                    <label for="edit_vehicle_type">Vehicle Type</label>
                    <select id="edit_vehicle_type" name="vehicle_type" required>
                        <option value="">Select vehicle type</option>
                        <option value="Car">Car</option>
                        <option value="Motorcycle">Motorcycle</option>
                        <option value="Truck">Truck</option>
                        <option value="N/A">N/A</option>
                    </select>
                </div>

                <div class="form-field">
                    <label for="edit_vehicle_model">Vehicle Model</label>
                    <select id="edit_vehicle_model" name="vehicle_model" required>
                        <option value="">Select vehicle model</option>
                        <option value="Toyota">Toyota</option>
                        <option value="Honda">Honda</option>
                        <option value="BMW">BMW</option>
                        <option value="N/A">N/A</option>
                    </select>
                </div>

                <div class="form-field">
                    <label for="edit_business_asset">Business Asset</label>
                    <select id="edit_business_asset" name="business_asset" required>
                        <option value="">Select business asset</option>
                        <option value="Shop">Shop</option>
                        <option value="Company">Company</option>
                        <option value="Factory">Factory</option>
                        <option value="N/A">N/A</option>
                    </select>
                </div>

                <button class="submit-btn" type="submit" name="edit_asset">Update Asset</button>
            </form>
        </div>
    </div>

    <!-- JavaScript for Modals and Actions -->
    <script>
        // Get modal elements
        const addAssetModal = document.getElementById("assetModal");
        const editAssetModal = document.getElementById("editAssetModal");

        // Get buttons that open the modals
        const addAssetBtn = document.getElementById("addAssetBtn");

        // Get the <span> elements that close the modals
        const closeModal = document.getElementById("closeModal");
        const closeEditModal = document.getElementById("closeEditModal");

        // When the user clicks the add button, open the modal 
        addAssetBtn.onclick = function() {
            addAssetModal.style.display = "flex";
        }

        // When the user clicks on <span> (x), close the modal
        closeModal.onclick = function() {
            addAssetModal.style.display = "none";
        }

        closeEditModal.onclick = function() {
            editAssetModal.style.display = "none";
        }

        // When the user clicks anywhere outside of the modal, close it
        window.onclick = function(event) {
            if (event.target == addAssetModal) {
                addAssetModal.style.display = "none";
            }
            if (event.target == editAssetModal) {
                editAssetModal.style.display = "none";
            }
        }

        // Function to fetch asset details and open edit modal
        function editAsset(assetId) {
            fetch('asset_details.php?id=' + assetId)
                .then(response => response.json())
                .then(data => {
                    if (!data.error) {
                        document.getElementById('asset_id').value = data.asset_id;
                        document.getElementById('edit_land_type').value = data.land_type;
                        document.getElementById('edit_land_amount').value = data.land_amount;
                        document.getElementById('edit_vehicle_type').value = data.vehicle_type;
                        document.getElementById('edit_vehicle_model').value = data.vehicle_model;
                        document.getElementById('edit_business_asset').value = data.business_asset;

                        editAssetModal.style.display = "flex";
                    } else {
                        alert(data.error);
                    }
                })
                .catch(error => {
                    console.error('Error fetching asset details:', error);
                });
        }

        // Function to delete asset
        function deleteAsset(assetId) {
            if (confirm("Are you sure you want to delete this asset?")) {
                const formData = new FormData();
                formData.append('delete_asset', true);
                formData.append('asset_id', assetId);

                fetch('', {
                    method: 'POST',
                    body: formData
                })
                .then(response => response.json())
                .then(result => {
                    if (result.success) {
                        alert("Asset deleted successfully!");
                        location.reload(); // Reload the page to see changes
                    } else {
                        alert("Error deleting asset.");
                    }
                })
                .catch(error => {
                    console.error('Error deleting asset:', error);
                });
            }
        }
    </script>
</body>
</html>
